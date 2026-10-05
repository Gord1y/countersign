import Foundation

public enum CursorAdapter {
  public static let shellEvent = "beforeShellExecution"
  public static let mcpEvent = "beforeMCPExecution"
  public static let events = [shellEvent, mcpEvent]
  public static let shellToolName = "Shell"

  public static func parse(_ data: Data) throws -> ApprovalRequest {
    let decoded: JSONValue
    do {
      decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      throw AdapterError.malformedInput("invalid JSON")
    }
    guard case .object(let root) = decoded else {
      throw AdapterError.malformedInput("expected a JSON object")
    }
    guard
      let sessionID = root["session_id"]?.stringValue ?? root["conversation_id"]?.stringValue
    else {
      throw AdapterError.malformedInput("missing session_id")
    }
    guard let event = root["hook_event_name"]?.stringValue else {
      throw AdapterError.malformedInput("missing hook_event_name")
    }

    let toolName: String
    let toolInput: JSONValue
    let body: ToolBody
    var runsInSandbox = false
    switch event {
    case shellEvent:
      guard let command = root["command"]?.stringValue else {
        throw AdapterError.malformedInput("missing command")
      }
      toolName = shellToolName
      toolInput = .object(["command": .string(command)])
      body = .bash(command: command, description: nil)
      runsInSandbox = root["sandbox"]?.boolValue ?? false
    case mcpEvent:
      guard let mcpToolName = root["tool_name"]?.stringValue else {
        throw AdapterError.malformedInput("missing tool_name")
      }
      toolName = mcpToolName
      toolInput = arguments(from: root["tool_input"])
      body = .mcp(server: serverName(in: root), tool: mcpToolName, arguments: toolInput)
    default:
      throw AdapterError.malformedInput("unexpected hook_event_name")
    }

    return ApprovalRequest(
      host: .cursor,
      sessionID: sessionID,
      cwd: workingDirectory(in: root),
      permissionMode: nil,
      transcriptPath: root["transcript_path"]?.stringValue,
      agentID: nil,
      agentType: nil,
      toolName: toolName,
      toolInput: toolInput,
      kind: .permission(PermissionPrompt(body: body, suggestions: [])),
      runsInSandbox: runsInSandbox
    )
  }

  public static func encode(_ outcome: ApprovalOutcome) -> Data? {
    switch outcome {
    case .addContext:
      return nil
    case .noDecision:
      return encodeReply(["permission": .string("ask")])
    case .allow:
      return encodeReply(["permission": .string("allow")])
    case .deny(let message, _):
      return encodeReply([
        "permission": .string("deny"),
        "user_message": .string(message),
        "agent_message": .string(message),
      ])
    }
  }

  private static func workingDirectory(in root: [String: JSONValue]) -> String {
    if let firstRoot = root["workspace_roots"]?.arrayValue?.first?.stringValue, !firstRoot.isEmpty {
      return firstRoot
    }
    return root["cwd"]?.stringValue ?? ""
  }

  private static func serverName(in root: [String: JSONValue]) -> String {
    let candidates = ["mcp_server_name", "mcp_server_url", "url", "command"]
    for key in candidates {
      if let value = root[key]?.stringValue, !value.isEmpty {
        return value
      }
    }
    return ""
  }

  private static func arguments(from value: JSONValue?) -> JSONValue {
    guard let value else { return .object([:]) }
    guard case .string(let text) = value else { return value }
    guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else {
      return value
    }
    return parsed
  }

  private static func encodeReply(_ reply: [String: JSONValue]) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try? encoder.encode(JSONValue.object(reply))
  }
}
