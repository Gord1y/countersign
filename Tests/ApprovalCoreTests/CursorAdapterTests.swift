import Foundation
import Testing

@testable import ApprovalCore

private func decodedReply(_ outcome: ApprovalOutcome) throws -> JSONValue {
  let data = try #require(CursorAdapter.encode(outcome))
  return try JSONDecoder().decode(JSONValue.self, from: data)
}

private func parse(_ json: String) throws -> ApprovalRequest {
  try CursorAdapter.parse(Data(json.utf8))
}

@Suite struct CursorAdapterTests {
  @Test func parsesTheShellFixture() throws {
    let request = try CursorAdapter.parse(FixtureLoader.data("cursor-shell"))
    #expect(request.host == .cursor)
    #expect(request.sessionID == "c3d4e5f6-a1b2-4c3d-8e9f-0a1b2c3d4e5f")
    #expect(request.cwd == "/Users/dev/Projects/shop-api")
    #expect(request.projectName == "shop-api")
    #expect(request.permissionMode == nil)
    #expect(request.agentID == nil)
    #expect(request.agentType == nil)
    #expect(request.transcriptPath?.hasSuffix(".jsonl") == true)
    #expect(request.toolName == "Shell")
    #expect(request.toolInput == .object(["command": .string("npm install stripe@14 --save")]))
    #expect(!request.runsInSandbox)
    let expected = PermissionPrompt(
      body: .bash(command: "npm install stripe@14 --save", description: nil), suggestions: [])
    #expect(request.kind == .permission(expected))
  }

  @Test func marksASandboxedShellCommand() throws {
    let request = try CursorAdapter.parse(FixtureLoader.data("cursor-shell-sandboxed"))
    #expect(request.runsInSandbox)
    guard case .permission(let prompt) = request.kind,
      case .bash(let command, _) = prompt.body
    else {
      Issue.record("expected bash body")
      return
    }
    #expect(command == "npm run lint -- --max-warnings 0")
  }

  @Test func readsTheFirstCallOfAChatWithoutATranscript() throws {
    let request = try CursorAdapter.parse(FixtureLoader.data("cursor-shell-first-call"))
    #expect(request.transcriptPath == nil)
    #expect(!request.runsInSandbox)
    #expect(request.projectName == "shop-api")
  }

  @Test func treatsAMissingOrOddSandboxFlagAsOutsideTheSandbox() throws {
    let missing = try parse(
      """
      {"session_id":"s","hook_event_name":"beforeShellExecution","command":"ls","workspace_roots":["/tmp/a"]}
      """)
    #expect(!missing.runsInSandbox)
    let odd = try parse(
      """
      {"session_id":"s","hook_event_name":"beforeShellExecution","command":"ls","sandbox":"yes"}
      """)
    #expect(!odd.runsInSandbox)
  }

  @Test func fallsBackToTheConversationForTheSession() throws {
    let request = try parse(
      """
      {"conversation_id":"conv","hook_event_name":"beforeShellExecution","command":"ls"}
      """)
    #expect(request.sessionID == "conv")
  }

  @Test func prefersTheSessionOverTheConversation() throws {
    let request = try parse(
      """
      {"session_id":"sess","conversation_id":"conv","hook_event_name":"beforeShellExecution","command":"ls"}
      """)
    #expect(request.sessionID == "sess")
  }

  @Test func fallsBackToTheCwdWithoutAWorkspaceRoot() throws {
    let emptyRoots = try parse(
      """
      {"session_id":"s","hook_event_name":"beforeShellExecution","command":"ls","cwd":"/tmp/web","workspace_roots":[]}
      """)
    #expect(emptyRoots.cwd == "/tmp/web")
    let blankRoot = try parse(
      """
      {"session_id":"s","hook_event_name":"beforeShellExecution","command":"ls","cwd":"/tmp/web","workspace_roots":[""]}
      """)
    #expect(blankRoot.cwd == "/tmp/web")
    let nothing = try parse(
      """
      {"session_id":"s","hook_event_name":"beforeShellExecution","command":"ls"}
      """)
    #expect(nothing.cwd == "")
  }

  @Test func parsesTheCapturedMCPShape() throws {
    let request = try CursorAdapter.parse(FixtureLoader.data("cursor-mcp-url"))
    #expect(request.toolName == "search_issues")
    #expect(!request.runsInSandbox)
    #expect(request.projectName == "shop-api")
    guard case .permission(let prompt) = request.kind,
      case .mcp(let server, let tool, let arguments) = prompt.body
    else {
      Issue.record("expected mcp body")
      return
    }
    #expect(server == "linear")
    #expect(tool == "search_issues")
    #expect(arguments["query"]?.stringValue == "legacy discount codes")
    #expect(arguments["limit"] == .int(5))
    #expect(request.toolInput == arguments)
  }

  @Test func namesTheServerByItsURLOrCommandWhenItHasNoName() throws {
    let cases: [(String, String)] = [
      (
        "\"mcp_server_url\":\"https://mcp.example.com\",\"url\":\"https://other\"",
        "https://mcp.example.com"
      ),
      ("\"url\":\"https://mcp.example.com\"", "https://mcp.example.com"),
      ("\"command\":\"npx server\"", "npx server"),
      ("\"mcp_server_name\":\"\",\"command\":\"npx server\"", "npx server"),
      ("\"other\":1", ""),
    ]
    for (fields, expected) in cases {
      let request = try parse(
        """
        {"session_id":"s","hook_event_name":"beforeMCPExecution","tool_name":"t","tool_input":"{}",\(fields)}
        """)
      guard case .permission(let prompt) = request.kind, case .mcp(let server, _, _) = prompt.body
      else {
        Issue.record("expected mcp body")
        continue
      }
      #expect(server == expected)
    }
  }

  @Test func readsToolInputAsAnObjectAStringOrNothing() throws {
    let inputs: [(String, JSONValue)] = [
      ("\"tool_input\":{\"a\":1}", .object(["a": .int(1)])),
      ("\"tool_input\":\"{\\\"a\\\":1}\"", .object(["a": .int(1)])),
      ("\"tool_input\":\"not json\"", .string("not json")),
      ("\"tool_input\":[1]", .array([.int(1)])),
      ("\"other\":1", .object([:])),
    ]
    for (fields, expected) in inputs {
      let request = try parse(
        """
        {"session_id":"s","hook_event_name":"beforeMCPExecution","tool_name":"t","mcp_server_name":"m",\(fields)}
        """)
      #expect(request.toolInput == expected)
    }
  }

  @Test func throwsOnInputItCannotRead() {
    let inputs = [
      "not json",
      "\"text\"",
      "{\"hook_event_name\":\"beforeShellExecution\",\"command\":\"ls\"}",
      "{\"session_id\":\"s\",\"command\":\"ls\"}",
      "{\"session_id\":\"s\",\"hook_event_name\":\"preToolUse\",\"command\":\"ls\"}",
      "{\"session_id\":\"s\",\"hook_event_name\":\"beforeShellExecution\"}",
      "{\"session_id\":\"s\",\"hook_event_name\":\"beforeMCPExecution\",\"tool_input\":{}}",
    ]
    let reasons = [
      "invalid JSON", "expected a JSON object", "missing session_id", "missing hook_event_name",
      "unexpected hook_event_name", "missing command", "missing tool_name",
    ]
    for (input, reason) in zip(inputs, reasons) {
      #expect(throws: AdapterError.malformedInput(reason)) {
        try parse(input)
      }
    }
  }

  @Test func encodesAllowWithoutAnyClaudeOnlyField() throws {
    let outcome = ApprovalOutcome.allow(
      updatedInput: .object(["x": .int(1)]),
      updatedPermissions: [.object(["type": .string("setMode")])])
    #expect(try decodedReply(outcome) == .object(["permission": .string("allow")]))
    #expect(try decodedReply(.allowAsIs) == .object(["permission": .string("allow")]))
  }

  @Test func encodesDenyForThePersonAndTheAgent() throws {
    let expected = JSONValue.object([
      "permission": .string("deny"),
      "user_message": .string("not on main"),
      "agent_message": .string("not on main"),
    ])
    #expect(try decodedReply(.deny(message: "not on main", interrupt: false)) == expected)
    #expect(try decodedReply(.deny(message: "not on main", interrupt: true)) == expected)
    let defaulted = try decodedReply(.deny(reason: "  ", interrupt: false))
    #expect(defaulted["user_message"]?.stringValue == ApprovalOutcome.defaultDenyMessage)
    #expect(defaulted["agent_message"]?.stringValue == ApprovalOutcome.defaultDenyMessage)
  }

  @Test func encodesNoDecisionAsAskSoCursorShowsItsOwnPrompt() throws {
    #expect(try decodedReply(.noDecision) == .object(["permission": .string("ask")]))
    let data = try #require(CursorAdapter.encode(.noDecision))
    #expect(String(decoding: data, as: UTF8.self) == "{\"permission\":\"ask\"}")
  }

  @Test func routesTheCursorHostThroughItsAdapter() throws {
    let parsedHost = ApprovalCore.Host(rawValue: "cursor")
    let host = try #require(parsedHost)
    #expect(host == .cursor)
    #expect(host.displayName == "Cursor")
    #expect(!host.supportsPermissionUpdates)
    #expect(!host.supportsInterrupt)
    #expect(host.handoffOutcome == .noDecision)
    let data = try FixtureLoader.data("cursor-shell")
    #expect(try host.parse(data) == CursorAdapter.parse(data))
    #expect(host.encode(.noDecision) == CursorAdapter.encode(.noDecision))
    #expect(ApprovalCore.Host.allCases == [.claude, .codex, .cursor, .antigravity])
  }

  @Test func namesTheEventsItAnswers() {
    #expect(CursorAdapter.events == ["beforeShellExecution", "beforeMCPExecution"])
  }

  @Test func encodesAddContextAsNil() {
    #expect(CursorAdapter.encode(.addContext("note")) == nil)
  }

  @Test func otherHostsNeverRunInASandbox() throws {
    #expect(!(try ClaudeAdapter.parse(FixtureLoader.data("claude-bash"))).runsInSandbox)
    #expect(!(try CodexAdapter.parse(FixtureLoader.data("codex-bash"))).runsInSandbox)
  }
}
