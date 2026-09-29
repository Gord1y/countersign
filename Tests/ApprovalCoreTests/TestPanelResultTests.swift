import Testing

@testable import ApprovalCore

@Suite struct TestPanelResultTests {
  private let suggestion: [JSONValue] = [.object(["type": .string("addRules")])]

  private func expectComplete(
    _ outcome: ApprovalOutcome, kind: TestPanelKind, choice: ContextCheckpointChoice? = nil,
    title expectedTitle: String
  ) {
    let result = TestPanelResult.describe(outcome, kind: kind, checkpointChoice: choice)
    #expect(result.title == expectedTitle)
    #expect(result.detail.hasSuffix("Nothing reached an agent."))
    #expect(result.detail.count > "Nothing reached an agent.".count)
  }

  @Test func commandAnswers() {
    expectComplete(.allowAsIs, kind: .command, title: "Approved")
    expectComplete(
      .allow(updatedInput: nil, updatedPermissions: suggestion), kind: .command,
      title: "Approved with a suggestion")
    expectComplete(
      .deny(reason: "no", interrupt: false), kind: .command, title: "Denied")
    expectComplete(
      .deny(reason: "no", interrupt: true), kind: .command, title: "Denied and stopped")
    expectComplete(.noDecision, kind: .command, title: "Answered in chat")
  }

  @Test func questionAnswers() {
    expectComplete(.allowAsIs, kind: .question, title: "Submitted")
    expectComplete(.noDecision, kind: .question, title: "Answered in chat")
  }

  @Test func planAnswers() {
    expectComplete(.allowAsIs, kind: .plan, title: "Approved")
    expectComplete(
      .deny(reason: "more", interrupt: false), kind: .plan, title: "Kept planning")
    expectComplete(.noDecision, kind: .plan, title: "Answered in chat")
  }

  @Test func contextAnswers() {
    expectComplete(.noDecision, kind: .context, title: "Continued")
    expectComplete(
      .noDecision, kind: .context, choice: .continueWorking, title: "Continued")
    expectComplete(
      .noDecision, kind: .context, choice: .notThisSession, title: "Not this session")
    expectComplete(
      .addContext("note"), kind: .context, choice: .compactAfterStep,
      title: "Compact after this step")
    expectComplete(
      .addContext("note"), kind: .context, choice: .handOff, title: "Hand off & start fresh")
  }

  @Test func aContextNoteChoiceQuotesTheFilledNote() {
    let request = TestPanelSample.contextRequest(
      level: .soft,
      settings: ContextCheckpointSettings.default)
    guard case .contextCheckpoint(let prompt) = request.kind else {
      Issue.record("expected a context checkpoint")
      return
    }
    for choice in [ContextCheckpointChoice.compactAfterStep, .handOff] {
      let outcome = choice.outcome(for: prompt)
      guard case .addContext(let note) = outcome else {
        Issue.record("expected a note")
        return
      }
      let result = TestPanelResult.describe(outcome, kind: .context, checkpointChoice: choice)
      #expect(result.detail.contains("\"\(note)\""))
      #expect(!note.contains("{tokens}"))
      #expect(!note.contains("{handoffFile}"))
      #expect(result.detail.contains(prompt.handoffFile) == note.contains(prompt.handoffFile))
    }
  }

  @Test func theResultLogLineIsFixed() {
    #expect(TestPanelLog.resultShown == "test panel: result shown")
  }
}
