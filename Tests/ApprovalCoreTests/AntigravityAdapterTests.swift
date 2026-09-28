import Foundation
import Testing

@testable import ApprovalCore

private func decodedReply(_ outcome: ApprovalOutcome) throws -> JSONValue {
  let data = try #require(AntigravityAdapter.encode(outcome))
  return try JSONDecoder().decode(JSONValue.self, from: data)
}

private func parse(_ json: String) throws -> ApprovalRequest {
  try AntigravityAdapter.parse(Data(json.utf8))
}

@Suite struct AntigravityAdapterTests {
  @Test func parsesTheRunCommandFixture() throws {
    let request = try AntigravityAdapter.parse(FixtureLoader.data("antigravity-run-command"))
    #expect(request.host == .antigravity)
    #expect(request.sessionID == "e1f2a3b4-c5d6-4e7f-8a9b-0c1d2e3f4a5b")
    #expect(request.cwd == "/Users/dev/Projects/shop-api")
    #expect(request.projectName == "shop-api")
    #expect(request.permissionMode == nil)
    #expect(request.agentID == nil)
    #expect(request.agentType == nil)
    #expect(
      request.transcriptPath?.hasSuffix("/.system_generated/logs/transcript_full.jsonl") == true)
    #expect(request.toolName == "run_command")
    #expect(request.toolInput["CommandLine"]?.stringValue == "npm install stripe@14 --save")
    #expect(request.toolInput["Cwd"]?.stringValue == "/Users/dev/Projects/shop-api")
    #expect(request.toolInput["WaitMsBeforeAsync"] == .int(10000))
    #expect(request.isAskedAbout)
    #expect(!request.runsInSandbox)
    let expected = PermissionPrompt(
      body: .bash(command: "npm install stripe@14 --save", description: "Install the Stripe SDK"),
      suggestions: [])
    #expect(request.kind == .permission(expected))
  }

  @Test func parsesTheMCPFixture() throws {
    let request = try AntigravityAdapter.parse(FixtureLoader.data("antigravity-mcp"))
    #expect(request.toolName == "create_issue")
    #expect(request.sessionID == "f2a3b4c5-d6e7-4f8a-9b0c-1d2e3f4a5b6c")
    #expect(request.projectName == "shop-api")
    #expect(request.isAskedAbout)
    guard case .permission(let prompt) = request.kind,
      case .mcp(let server, let tool, let arguments) = prompt.body
    else {
      Issue.record("expected mcp body")
      return
    }
    #expect(server == "github")
    #expect(tool == "create_issue")
    #expect(arguments["title"]?.stringValue == "Discount rate cap is not enforced on legacy codes")
    #expect(arguments["labels"] == .array([.string("bug")]))
    #expect(arguments["toolSummary"] == nil)
    #expect(request.toolInput == arguments)
  }

  @Test func skipsEveryOtherToolAfterParsingIt() throws {
    let request = try AntigravityAdapter.parse(FixtureLoader.data("antigravity-view-file"))
    #expect(!request.isAskedAbout)
    #expect(request.toolName == "view_file")
    #expect(request.projectName == "shop-api")
    #expect(
      request.toolInput["AbsolutePath"]?.stringValue
        == "/Users/dev/Projects/shop-api/src/pricing/discount.ts")
    #expect(
      request.kind == .permission(PermissionPrompt(body: .json(request.toolInput), suggestions: []))
    )
    for name in ["write_to_file", "grep_search", "browser_subagent", "Run_Command", ""] {
      let other = try parse(
        """
        {"conversationId":"c","toolCall":{"name":"\(name)","args":{"CommandLine":"ls"}}}
        """)
      #expect(!other.isAskedAbout)
      #expect(other.toolName == name)
    }
  }

  @Test func asksAboutCommandsAndMCPCallsOnly() {
    #expect(AntigravityAdapter.askedTools == ["run_command", "call_mcp_tool"])
    #expect(AntigravityAdapter.event == "PreToolUse")
  }

  @Test func leavesTheDescriptionOutWithoutASummary() throws {
    let missing = try parse(
      """
      {"conversationId":"c","toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}
      """)
    let empty = try parse(
      """
      {"conversationId":"c","toolCall":{"name":"run_command","args":{"CommandLine":"ls","toolSummary":""}}}
      """)
    let odd = try parse(
      """
      {"conversationId":"c","toolCall":{"name":"run_command","args":{"CommandLine":"ls","toolSummary":3}}}
      """)
    for request in [missing, empty, odd] {
      #expect(
        request.kind
          == .permission(
            PermissionPrompt(body: .bash(command: "ls", description: nil), suggestions: [])))
    }
  }

  @Test func namesTheProjectAfterTheFirstWorkspace() throws {
    let nested = try parse(
      """
      {"conversationId":"c","workspacePaths":["/tmp/web","/tmp/api"],"toolCall":{"name":"run_command","args":{"CommandLine":"ls","Cwd":"/tmp/web/src"}}}
      """)
    #expect(nested.cwd == "/tmp/web")
    #expect(nested.projectName == "web")
    #expect(nested.toolInput["Cwd"]?.stringValue == "/tmp/web/src")
  }

  @Test func fallsBackToTheCommandsDirectoryWithoutAWorkspace() throws {
    let emptyPaths = try parse(
      """
      {"conversationId":"c","workspacePaths":[],"toolCall":{"name":"run_command","args":{"CommandLine":"ls","Cwd":"/tmp/web"}}}
      """)
    #expect(emptyPaths.cwd == "/tmp/web")
    let blankPath = try parse(
      """
      {"conversationId":"c","workspacePaths":[""],"toolCall":{"name":"run_command","args":{"CommandLine":"ls","Cwd":"/tmp/web"}}}
      """)
    #expect(blankPath.cwd == "/tmp/web")
    let nothing = try parse(
      """
      {"conversationId":"c","toolCall":{"name":"run_command","args":{"CommandLine":"ls"}}}
      """)
    #expect(nothing.cwd == "")
    #expect(nothing.transcriptPath == nil)
  }

  @Test func readsAnMCPCallWithoutAServerOrArguments() throws {
    let request = try parse(
      """
      {"conversationId":"c","toolCall":{"name":"call_mcp_tool","args":{"ToolName":"t"}}}
      """)
    #expect(request.toolInput == .object([:]))
    #expect(
      request.kind
        == .permission(
          PermissionPrompt(
            body: .mcp(server: "", tool: "t", arguments: .object([:])), suggestions: [])
        ))
  }

  @Test func readsAToolCallWithoutArguments() throws {
    let request = try parse(
      """
      {"conversationId":"c","toolCall":{"name":"list_dir"}}
      """)
    #expect(request.toolInput == .object([:]))
    #expect(!request.isAskedAbout)
  }

  @Test func throwsOnInputItCannotRead() {
    let inputs = [
      "not json",
      "[1]",
      "{\"toolCall\":{\"name\":\"run_command\",\"args\":{\"CommandLine\":\"ls\"}}}",
      "{\"conversationId\":\"c\"}",
      "{\"conversationId\":\"c\",\"toolCall\":\"run_command\"}",
      "{\"conversationId\":\"c\",\"toolCall\":{\"args\":{}}}",
      "{\"conversationId\":\"c\",\"toolCall\":{\"name\":\"run_command\",\"args\":{\"Cwd\":\"/tmp\"}}}",
      "{\"conversationId\":\"c\",\"toolCall\":{\"name\":\"call_mcp_tool\",\"args\":{\"ServerName\":\"s\"}}}",
    ]
    let reasons = [
      "invalid JSON", "expected a JSON object", "missing conversationId", "missing toolCall",
      "missing toolCall", "missing toolCall.name", "missing CommandLine", "missing ToolName",
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
    #expect(try decodedReply(outcome) == .object(["decision": .string("allow")]))
    let data = try #require(AntigravityAdapter.encode(.allowAsIs))
    #expect(String(decoding: data, as: UTF8.self) == "{\"decision\":\"allow\"}")
  }

  @Test func encodesDenyWithItsReason() throws {
    let expected = JSONValue.object(["decision": .string("deny"), "reason": .string("not on main")])
    #expect(try decodedReply(.deny(message: "not on main", interrupt: false)) == expected)
    #expect(try decodedReply(.deny(message: "not on main", interrupt: true)) == expected)
    let defaulted = try decodedReply(.deny(reason: "  ", interrupt: false))
    #expect(defaulted["reason"]?.stringValue == ApprovalOutcome.defaultDenyMessage)
    let data = try #require(AntigravityAdapter.encode(.deny(message: "a/b", interrupt: false)))
    #expect(String(decoding: data, as: UTF8.self) == "{\"decision\":\"deny\",\"reason\":\"a/b\"}")
  }

  @Test func encodesNoDecisionAsAskSoAntigravityShowsItsOwnPrompt() throws {
    let data = try #require(AntigravityAdapter.encode(.noDecision))
    #expect(String(decoding: data, as: UTF8.self) == "{\"decision\":\"ask\"}")
  }

  @Test func routesTheAntigravityHostThroughItsAdapter() throws {
    let parsedHost = ApprovalCore.Host(rawValue: "antigravity")
    let host = try #require(parsedHost)
    #expect(host == .antigravity)
    #expect(host.displayName == "Antigravity")
    #expect(!host.supportsPermissionUpdates)
    #expect(!host.supportsInterrupt)
    #expect(host.handoffOutcome == .noDecision)
    let data = try FixtureLoader.data("antigravity-run-command")
    #expect(try host.parse(data) == AntigravityAdapter.parse(data))
    #expect(host.encode(.noDecision) == AntigravityAdapter.encode(.noDecision))
    #expect(ApprovalCore.Host.allCases == [.claude, .codex, .cursor, .antigravity])
  }

  @Test func otherHostsAreAskedAboutEveryRequestTheyParse() throws {
    #expect(try ClaudeAdapter.parse(FixtureLoader.data("claude-bash")).isAskedAbout)
    #expect(try CodexAdapter.parse(FixtureLoader.data("codex-bash")).isAskedAbout)
    #expect(try CursorAdapter.parse(FixtureLoader.data("cursor-shell-sandboxed")).isAskedAbout)
    #expect(try CursorAdapter.parse(FixtureLoader.data("cursor-mcp-url")).isAskedAbout)
  }
}
