import Foundation
import Testing

@testable import ApprovalCore

@Suite struct TestPanelTests {
  private static let fixtureForKind: [TestPanelKind: String] = [
    .command: "claude-bash",
    .question: "claude-questions",
    .plan: "claude-plan",
  ]

  private static func keyPaths(_ value: JSONValue, prefix: String = "") -> Set<String> {
    switch value {
    case .object(let object):
      return object.reduce(into: Set<String>()) { paths, element in
        let path = prefix.isEmpty ? element.key : "\(prefix).\(element.key)"
        paths.insert(path)
        paths.formUnion(keyPaths(element.value, prefix: path))
      }
    case .array(let elements):
      return elements.reduce(into: Set<String>()) { paths, element in
        paths.formUnion(keyPaths(element, prefix: "\(prefix)[]"))
      }
    case .null, .bool, .int, .double, .string:
      return []
    }
  }

  @Test func noArgumentsMeansACommand() {
    #expect(TestPanelKind.parse([]) == .command)
  }

  @Test func eachKindIsNamedByItsRawValue() {
    #expect(TestPanelKind.parse(["command"]) == .command)
    #expect(TestPanelKind.parse(["question"]) == .question)
    #expect(TestPanelKind.parse(["plan"]) == .plan)
    #expect(TestPanelKind.allCases.map(\.rawValue) == ["command", "question", "plan"])
  }

  @Test func eachKindHasAButtonTitle() {
    #expect(TestPanelKind.allCases.map(\.title) == ["Command", "Question", "Plan"])
  }

  @Test func anUnknownKindOrAnExtraArgumentIsRejected() {
    #expect(TestPanelKind.parse(["questions"]) == nil)
    #expect(TestPanelKind.parse(["--help"]) == nil)
    #expect(TestPanelKind.parse([""]) == nil)
    #expect(TestPanelKind.parse(["command", "plan"]) == nil)
  }

  @Test(arguments: TestPanelKind.allCases)
  func everySampleUsesOnlyKeysItsCapturedFixtureHas(_ kind: TestPanelKind) throws {
    let fixtureName = try #require(Self.fixtureForKind[kind])
    let fixture = try JSONDecoder().decode(JSONValue.self, from: FixtureLoader.data(fixtureName))

    let sampleKeys = Self.keyPaths(TestPanelSample.payload(for: kind))
    let fixtureKeys = Self.keyPaths(fixture)

    #expect(sampleKeys.subtracting(fixtureKeys).isEmpty)
    #expect(sampleKeys.contains("tool_input"))
    #expect(fixtureKeys.contains("transcript_path"))
    #expect(!sampleKeys.contains("transcript_path"))
    #expect(!sampleKeys.contains("agent_id"))
  }

  @Test(arguments: TestPanelKind.allCases)
  func everySampleIsAClaudeRequestFromTheCountersignTestProject(_ kind: TestPanelKind) throws {
    let request = try TestPanelSample.request(for: kind)

    #expect(request.host == .claude)
    #expect(request.cwd == TestPanelSample.workingDirectory)
    #expect(request.projectName == "Countersign test")
    #expect(request.sessionID == TestPanelSample.sessionID)
    #expect(request.transcriptPath == nil)
    #expect(request.agentID == nil)
    #expect(request.agentType == nil)
    #expect(!request.runsInSandbox)
    #expect(request.isAskedAbout)
    #expect(TicketSummary(request: request).project == "Countersign test")
  }

  @Test func theCommandSampleIsAGitPushWithOneAlwaysAllowRule() throws {
    let request = try TestPanelSample.request(for: .command)

    #expect(request.toolName == "Bash")
    #expect(request.permissionMode == "default")
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected a permission prompt")
      return
    }
    #expect(
      prompt.body
        == .bash(command: "git push origin main", description: "Push the main branch to origin"))
    #expect(
      prompt.suggestions.map(\.label) == [
        "Always allow Bash(git push origin *) (this project, local)"
      ])
  }

  @Test func theQuestionSampleHasTwoQuestionsAndOnlyTheSecondIsMultiSelect() throws {
    let request = try TestPanelSample.request(for: .question)

    #expect(request.toolName == "AskUserQuestion")
    #expect(request.permissionMode == "default")
    guard case .questions(let questions) = request.kind else {
      Issue.record("expected questions")
      return
    }
    #expect(questions.map(\.header) == ["Format", "Sections"])
    #expect(questions.map(\.multiSelect) == [false, true])
    #expect(questions[0].question == "Which date format should the report use?")
    #expect(questions[0].options.map(\.label) == ["ISO 8601", "Day first", "Month first"])
    #expect(
      questions[0].options.map(\.description) == ["2026-09-28", "28.09.2026", "09.28.2026"])
    #expect(questions[1].question == "Which sections should the report include?")
    #expect(questions[1].options.map(\.label) == ["Summary", "Charts", "Raw data"])
    #expect(questions[1].options.allSatisfy { $0.description == nil && $0.preview == nil })
  }

  @Test func thePlanSampleIsAShortMarkdownPlanInPlanMode() throws {
    let request = try TestPanelSample.request(for: .plan)

    #expect(request.toolName == "ExitPlanMode")
    #expect(request.permissionMode == "plan")
    guard case .plan(let proposal) = request.kind else {
      Issue.record("expected a plan")
      return
    }
    #expect(proposal.planFilePath == nil)
    #expect(proposal.plan.hasPrefix("# Add a changelog\n"))
    #expect(proposal.plan.hasSuffix("Nothing else changes."))
    let blocks = MarkdownBlocks.parse(proposal.plan)
    #expect(blocks.count > 3)
  }

  @Test func theStartLineNamesTheKind() {
    #expect(TestPanelLog.start(.command) == "test panel: start kind=command")
    #expect(TestPanelLog.start(.question) == "test panel: start kind=question")
    #expect(TestPanelLog.start(.plan) == "test panel: start kind=plan")
  }

  @Test func commandOutcomesReadAsTheButtonsThatMadeThem() {
    let suggestion: JSONValue = .object(["type": .string("addRules")])

    #expect(TestPanelLog.outcome(.allowAsIs, kind: .command) == "test panel: approved")
    #expect(
      TestPanelLog.outcome(
        .allow(updatedInput: nil, updatedPermissions: [suggestion]), kind: .command)
        == "test panel: approved with a suggestion")
    #expect(
      TestPanelLog.outcome(.deny(reason: "", interrupt: false), kind: .command)
        == "test panel: denied")
    #expect(
      TestPanelLog.outcome(.deny(reason: "not now", interrupt: true), kind: .command)
        == "test panel: denied and stopped")
    #expect(TestPanelLog.outcome(.noDecision, kind: .command) == "test panel: answered in chat")
  }

  @Test func questionOutcomesReadAsSubmittedOrAnsweredInChat() {
    let answers: JSONValue = .object(["answers": .object([:])])

    #expect(
      TestPanelLog.outcome(.allow(updatedInput: answers, updatedPermissions: []), kind: .question)
        == "test panel: submitted")
    #expect(TestPanelLog.outcome(.noDecision, kind: .question) == "test panel: answered in chat")
    #expect(
      TestPanelLog.outcome(.deny(reason: "", interrupt: false), kind: .question)
        == "test panel: denied")
    #expect(
      TestPanelLog.outcome(.deny(reason: "", interrupt: true), kind: .question)
        == "test panel: denied and stopped")
  }

  @Test func planOutcomesReadAsApprovedOrKeptPlanning() {
    let planInput = TestPanelSample.payload(for: .plan)["tool_input"] ?? .null

    #expect(
      TestPanelLog.outcome(
        PlanResponse.approve(toolInput: planInput, mode: .acceptEdits), kind: .plan)
        == "test panel: approved")
    #expect(
      TestPanelLog.outcome(PlanResponse.keepPlanning(feedback: "more detail"), kind: .plan)
        == "test panel: kept planning")
    #expect(
      TestPanelLog.outcome(.deny(message: "stop", interrupt: true), kind: .plan)
        == "test panel: kept planning")
    #expect(TestPanelLog.outcome(.noDecision, kind: .plan) == "test panel: answered in chat")
  }

  @Test func aSnoozeSaysNoQuietTimeStarted() {
    #expect(
      TestPanelLog.snooze(seconds: 60)
        == "test panel: snoozed for 1 minute, quiet time not started")
    #expect(
      TestPanelLog.snooze(seconds: 15 * 60)
        == "test panel: snoozed for 15 minutes, quiet time not started")
    #expect(
      TestPanelLog.snooze(seconds: 3600)
        == "test panel: snoozed for 1 hour, quiet time not started")
  }

  @Test func aRefusalNamesWhatToAnswerFirst() {
    #expect(
      TestPanelLog.refused(.panelOnScreen)
        == "test panel: refused (a panel is already on screen; answer it first)")
    #expect(
      TestPanelLog.refused(.requestWaiting)
        == "test panel: refused (a request is waiting for a panel; answer it first)")
  }

  @Test func closingForARealRequestSaysSo() {
    #expect(TestPanelLog.closedForRealRequest == "test panel: closed for a real request")
  }
}
