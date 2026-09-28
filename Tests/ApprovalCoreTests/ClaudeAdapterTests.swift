import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ClaudeAdapterTests {
  @Test func parsesBashFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash"))
    #expect(request.host == .claude)
    #expect(request.projectName == "shop-api")
    #expect(request.permissionMode == "default")
    #expect(request.agentID == nil)
    #expect(request.agentType == nil)
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .bash(let command, let description) = prompt.body else {
      Issue.record("expected bash body")
      return
    }
    #expect(command == "git push --force-with-lease origin feature/x && echo \"done $HOME\"")
    #expect(description == "Push the feature branch and confirm completion")
    #expect(prompt.suggestions.count == 2)
    #expect(
      prompt.suggestions[0].label
        == "Always allow Bash(git push --force-with-lease origin *) (this project, local)"
    )
    #expect(
      prompt.suggestions[1].label
        == "Always allow access to /Users/dev/Projects/shop-api (this session)"
    )
  }

  @Test func parsesBashSubagentFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash-subagent"))
    #expect(request.agentID == "a1b2c3d4")
    #expect(request.agentType == "Explore")
    #expect(request.transcriptPath?.hasSuffix(".jsonl") == true)
  }

  @Test func parsesBashLongFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash-long"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .bash(let command, let description) = prompt.body else {
      Issue.record("expected bash body")
      return
    }
    let token =
      "8oKQyZL3b4_k3y_z87cv24vfJpKpI_GiPM5H_X7iGq_-GoWynBysP6IF9NNYdGEi_MDu4_PehiecbYIffvupnelehYtX88MtwPzld0q2BUsyHyT2rYMDr2GFgnsiVkWVmJVKJXfUMPbLCzoP1gl-JSanivCEtyyv5V9_ol7nLM1Yt4qfnTrCfw03cWGbPLi6serfQwMquQjPg-aNgI5mealNjA29JYZN-TCYjHjOAs37-djGvXMB_XyZag91hfwLNZ9fTjP7XqqNdQ9o-Ni9S4QXw64M21VBECbLsZx8adkV"
    #expect(command.count > 600)
    #expect(token.count == 300)
    #expect(!token.contains(" "))
    #expect(command.contains(token))
    #expect(description == "Notify the deploy webhook and upload the release artifact to S3")
  }

  @Test func parsesEditFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-edit"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .edit(let path, let oldString, let newString, let replaceAll) = prompt.body else {
      Issue.record("expected edit body")
      return
    }
    #expect(path == "/Users/dev/Projects/shop-api/Sources/Checkout/DiscountCalculator.swift")
    #expect(oldString.contains("func applyDiscount"))
    #expect(newString.contains("maximumDiscountRate"))
    #expect(replaceAll == false)
    #expect(prompt.suggestions.map(\.label) == ["Allow and switch to acceptEdits"])
  }

  @Test func parsesEditLongFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-edit-long"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .edit(let path, let oldString, let newString, let replaceAll) = prompt.body else {
      Issue.record("expected edit body")
      return
    }
    #expect(path == "/Users/dev/Projects/shop-api/Sources/FeatureFlags/FeatureFlagEvaluator.swift")
    #expect(oldString.split(separator: "\n", omittingEmptySubsequences: false).count >= 70)
    #expect(newString.split(separator: "\n", omittingEmptySubsequences: false).count >= 70)
    #expect(oldString.contains("struct FeatureFlagEvaluator"))
    #expect(newString.contains("prioritySupport"))
    #expect(replaceAll == false)
  }

  @Test func parsesWriteFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-write"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .write(let path, let content) = prompt.body else {
      Issue.record("expected write body")
      return
    }
    #expect(path == "/Users/dev/Projects/shop-api/Sources/Checkout/ShippingRates.swift")
    #expect(content.split(separator: "\n").count >= 60)
  }

  @Test func parsesWebFetchFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-webfetch"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .webFetch(let url, let prompt) = prompt.body else {
      Issue.record("expected webFetch body")
      return
    }
    #expect(url == "https://developer.stripe.com/docs/webhooks/signatures")
    #expect(prompt == "Summarize how webhook signature verification works")
  }

  @Test func parsesMCPFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-mcp"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .mcp(let server, let tool, let arguments) = prompt.body else {
      Issue.record("expected mcp body")
      return
    }
    #expect(server == "postgres")
    #expect(tool == "query")
    #expect(arguments["sql"]?.stringValue?.contains("SELECT") == true)
  }

  @Test func parsesOtherToolAsJSON() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-other"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .json(let value) = prompt.body else {
      Issue.record("expected json body")
      return
    }
    #expect(value["notebook_path"]?.stringValue != nil)
  }

  @Test func parsesQuestionsFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-questions"))
    guard case .questions(let questions) = request.kind else {
      Issue.record("expected questions")
      return
    }
    #expect(questions.count == 3)
    #expect(questions[0].header == "Storage")
    #expect(questions[0].multiSelect == false)
    #expect(questions[0].options.count == 3)
    #expect(questions[0].options[0].preview?.contains("\n") == true)
    #expect(questions[1].header == "Targets")
    #expect(questions[1].multiSelect == true)
    #expect(questions[1].options.count == 4)
    #expect(questions[2].header == "Rollout")
    #expect(questions[2].options.allSatisfy { $0.description != nil })
  }

  @Test func parsesPlanFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-plan"))
    #expect(request.permissionMode == "plan")
    guard case .plan(let plan) = request.kind else {
      Issue.record("expected plan")
      return
    }
    #expect(plan.plan.contains("# Add discount code support"))
    #expect(plan.planFilePath == "/Users/dev/Projects/shop-api/.claude/plans/discount-codes.md")
  }

  @Test func parsesPlanLongFixture() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-plan-long"))
    #expect(request.permissionMode == "plan")
    guard case .plan(let plan) = request.kind else {
      Issue.record("expected plan")
      return
    }
    #expect(plan.plan.contains("# Migrate the pricing engine to tiered plans"))
    #expect(plan.plan.split(separator: "\n", omittingEmptySubsequences: false).count >= 140)
    #expect(plan.plan.contains("```swift"))
    #expect(plan.plan.contains("```sql"))
    #expect(plan.planFilePath == "/Users/dev/Projects/shop-api/.claude/plans/tiered-pricing.md")

    let blocks = MarkdownBlocks.parse(plan.plan)
    #expect(blocks.contains { if case .code = $0 { return true } else { return false } })
    #expect(
      blocks.filter {
        if case .code = $0 { return true } else { return false }
      }.count == 2)
  }

  @Test func suggestionLabelUsesBehaviorVerbWhenNotAllow() throws {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"Bash",
        "tool_input":{"command":"ls"},
        "permission_suggestions":[
          {
            "type":"addRules",
            "rules":[{"toolName":"Bash","ruleContent":"ls *"}],
            "behavior":"deny",
            "destination":"localSettings"
          }
        ]
      }
      """
    let request = try ClaudeAdapter.parse(Data(json.utf8))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    #expect(prompt.suggestions.map(\.label) == ["Always deny Bash(ls *) (this project, local)"])
  }

  @Test func projectNameFallsBackToCWDWhenEmpty() {
    let request = ApprovalRequest(
      host: .claude,
      sessionID: "s",
      cwd: "",
      permissionMode: nil,
      transcriptPath: nil,
      agentID: nil,
      agentType: nil,
      toolName: "Bash",
      toolInput: .object([:]),
      kind: .permission(PermissionPrompt(body: .json(.object([:])), suggestions: []))
    )
    #expect(request.projectName == "")
  }

  @Test func throwsWhenNotAnObject() {
    #expect(throws: AdapterError.self) {
      _ = try ClaudeAdapter.parse(Data("[]".utf8))
    }
  }

  @Test func throwsWhenSessionIDMissing() {
    let json = """
      {"cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"ls"}}
      """
    #expect(throws: AdapterError.self) {
      _ = try ClaudeAdapter.parse(Data(json.utf8))
    }
  }

  @Test func throwsWhenToolInputIsNotAnObject() {
    let json = """
      {"session_id":"s","cwd":"/tmp","tool_name":"Bash","tool_input":"ls"}
      """
    #expect(throws: AdapterError.self) {
      _ = try ClaudeAdapter.parse(Data(json.utf8))
    }
  }

  @Test func throwsWhenHookEventNameIsWrong() {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"Bash",
        "tool_input":{"command":"ls"},"hook_event_name":"PreToolUse"
      }
      """
    #expect(throws: AdapterError.self) {
      _ = try ClaudeAdapter.parse(Data(json.utf8))
    }
  }

  @Test func throwsOnMalformedAskUserQuestion() {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"AskUserQuestion",
        "tool_input":{"questions":[]}
      }
      """
    #expect(throws: AdapterError.self) {
      _ = try ClaudeAdapter.parse(Data(json.utf8))
    }
  }

  @Test func throwsOnExitPlanModeWithoutPlan() {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"ExitPlanMode",
        "tool_input":{}
      }
      """
    #expect(throws: AdapterError.self) {
      _ = try ClaudeAdapter.parse(Data(json.utf8))
    }
  }

  @Test func encodesNoDecisionAsNil() {
    #expect(ClaudeAdapter.encode(.noDecision) == nil)
  }

  @Test func handsOffWithNoReplyOfItsOwn() {
    #expect(Host.claude.handoffOutcome == nil)
  }

  @Test func encodesAllowAsIs() throws {
    let data = try #require(ClaudeAdapter.encode(.allowAsIs))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let expected = JSONValue.object([
      "hookSpecificOutput": .object([
        "hookEventName": .string("PermissionRequest"),
        "decision": .object(["behavior": .string("allow")]),
      ])
    ])
    #expect(decoded == expected)
  }

  @Test func encodesAllowWithUpdatedInputAndPermissions() throws {
    let outcome = ApprovalOutcome.allow(
      updatedInput: .object(["plan": .string("do it")]),
      updatedPermissions: [.object(["type": .string("setMode"), "mode": .string("auto")])]
    )
    let data = try #require(ClaudeAdapter.encode(outcome))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let expected = JSONValue.object([
      "hookSpecificOutput": .object([
        "hookEventName": .string("PermissionRequest"),
        "decision": .object([
          "behavior": .string("allow"),
          "updatedInput": .object(["plan": .string("do it")]),
          "updatedPermissions": .array([
            .object(["type": .string("setMode"), "mode": .string("auto")])
          ]),
        ]),
      ])
    ])
    #expect(decoded == expected)
  }

  @Test func encodesDenyWithInterrupt() throws {
    let data = try #require(ClaudeAdapter.encode(.deny(message: "no", interrupt: true)))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let expected = JSONValue.object([
      "hookSpecificOutput": .object([
        "hookEventName": .string("PermissionRequest"),
        "decision": .object([
          "behavior": .string("deny"),
          "message": .string("no"),
          "interrupt": .bool(true),
        ]),
      ])
    ])
    #expect(decoded == expected)
  }

  @Test func denyReasonDefaultsWhenBlank() throws {
    let outcome = ApprovalOutcome.deny(reason: "   ", interrupt: false)
    let data = try #require(ClaudeAdapter.encode(outcome))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let message = decoded["hookSpecificOutput"]?["decision"]?["message"]?.stringValue
    #expect(message == ApprovalOutcome.defaultDenyMessage)
  }
}
