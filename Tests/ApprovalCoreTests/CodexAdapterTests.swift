import Foundation
import Testing

@testable import ApprovalCore

@Suite struct CodexAdapterTests {
  @Test func parsesBashStringFixture() throws {
    let request = try CodexAdapter.parse(FixtureLoader.data("codex-bash"))
    #expect(request.host == .codex)
    #expect(request.transcriptPath == nil)
    #expect(request.projectName == "shop-api")
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .bash(let command, let description) = prompt.body else {
      Issue.record("expected bash body")
      return
    }
    #expect(command == "npm run lint -- --max-warnings 0")
    #expect(description == nil)
    #expect(prompt.suggestions.isEmpty)
  }

  @Test func parsesBashArgvWithShellFlagScriptShape() throws {
    let request = try CodexAdapter.parse(FixtureLoader.data("codex-bash-argv"))
    guard case .permission(let prompt) = request.kind,
      case .bash(let command, _) = prompt.body
    else {
      Issue.record("expected bash body")
      return
    }
    #expect(command == "rm -rf build && npm run build")
  }

  @Test func joinsArbitraryArgvWithQuoting() throws {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"Bash",
        "tool_input":{"command":["git","commit","-m","fix: handle empty carts","--no-verify"]}
      }
      """
    let request = try CodexAdapter.parse(Data(json.utf8))
    guard case .permission(let prompt) = request.kind,
      case .bash(let command, _) = prompt.body
    else {
      Issue.record("expected bash body")
      return
    }
    #expect(command == "git commit -m 'fix: handle empty carts' --no-verify")
  }

  @Test func quotesEmptyAndSpecialArgvElements() throws {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"Bash",
        "tool_input":{"command":["echo","","a|b","it's"]}
      }
      """
    let request = try CodexAdapter.parse(Data(json.utf8))
    guard case .permission(let prompt) = request.kind,
      case .bash(let command, _) = prompt.body
    else {
      Issue.record("expected bash body")
      return
    }
    #expect(command == "echo '' 'a|b' 'it'\\''s'")
  }

  @Test func parsesApplyPatchFixture() throws {
    let request = try CodexAdapter.parse(FixtureLoader.data("codex-apply-patch"))
    guard case .permission(let prompt) = request.kind,
      case .patch(let text) = prompt.body
    else {
      Issue.record("expected patch body")
      return
    }
    #expect(text.contains("*** Begin Patch"))
    #expect(text.contains("*** Add File: Sources/Checkout/DiscountCalculator.swift"))
    #expect(text.contains("*** Move to: Sources/Checkout/CheckoutService.swift"))
    #expect(text.contains("*** Delete File: Sources/Checkout/LegacyDiscount.swift"))
    #expect(text.contains("*** End Patch"))
  }

  @Test func joinsApplyPatchArrayWithoutBeginPatchMarker() throws {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"apply_patch",
        "tool_input":{"command":["line one","line two"]}
      }
      """
    let request = try CodexAdapter.parse(Data(json.utf8))
    guard case .permission(let prompt) = request.kind,
      case .patch(let text) = prompt.body
    else {
      Issue.record("expected patch body")
      return
    }
    #expect(text == "line one\nline two")
  }

  @Test func parsesMCPFixture() throws {
    let request = try CodexAdapter.parse(FixtureLoader.data("codex-mcp"))
    guard case .permission(let prompt) = request.kind,
      case .mcp(let server, let tool, let arguments) = prompt.body
    else {
      Issue.record("expected mcp body")
      return
    }
    #expect(server == "github")
    #expect(tool == "create_issue")
    #expect(arguments["title"]?.stringValue != nil)
  }

  @Test func fallsBackToJSONWhenCommandMissing() throws {
    let json = """
      {
        "session_id":"s","cwd":"/tmp","tool_name":"Bash",
        "tool_input":{"note":"no command here"}
      }
      """
    let request = try CodexAdapter.parse(Data(json.utf8))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return
    }
    guard case .json(let value) = prompt.body else {
      Issue.record("expected json body")
      return
    }
    #expect(value["note"]?.stringValue == "no command here")
  }

  @Test func throwsWhenNotAnObject() {
    #expect(throws: AdapterError.self) {
      _ = try CodexAdapter.parse(Data("\"oops\"".utf8))
    }
  }

  @Test func throwsWhenCWDMissing() {
    let json = """
      {"session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}
      """
    #expect(throws: AdapterError.self) {
      _ = try CodexAdapter.parse(Data(json.utf8))
    }
  }

  @Test func encodesAllowWithoutClaudeOnlyFields() throws {
    let outcome = ApprovalOutcome.allow(
      updatedInput: .object(["x": .int(1)]),
      updatedPermissions: [.object(["type": .string("setMode")])]
    )
    let data = try #require(CodexAdapter.encode(outcome))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let expected = JSONValue.object([
      "hookSpecificOutput": .object([
        "hookEventName": .string("PermissionRequest"),
        "decision": .object(["behavior": .string("allow")]),
      ])
    ])
    #expect(decoded == expected)
  }

  @Test func encodesDenyWithoutInterrupt() throws {
    let data = try #require(CodexAdapter.encode(.deny(message: "blocked", interrupt: true)))
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let expected = JSONValue.object([
      "hookSpecificOutput": .object([
        "hookEventName": .string("PermissionRequest"),
        "decision": .object([
          "behavior": .string("deny"),
          "message": .string("blocked"),
        ]),
      ])
    ])
    #expect(decoded == expected)
  }

  @Test func encodesNoDecisionAsNil() {
    #expect(CodexAdapter.encode(.noDecision) == nil)
  }

  @Test func handsOffWithNoReplyOfItsOwn() {
    #expect(Host.codex.handoffOutcome == nil)
  }
}
