import Foundation

public enum AntigravityAdapter {
  public static let event = "PreToolUse"
  public static let commandTool = "run_command"
  public static let mcpTool = "call_mcp_tool"
  public static let askedTools = [commandTool, mcpTool]

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
    guard let sessionID = root["conversationId"]?.stringValue else {
      throw AdapterError.malformedInput("missing conversationId")
    }
    guard let toolCall = root["toolCall"]?.objectValue else {
      throw AdapterError.malformedInput("missing toolCall")
    }
    guard let callName = toolCall["name"]?.stringValue else {
      throw AdapterError.malformedInput("missing toolCall.name")
    }
    let arguments = toolCall["args"]?.objectValue ?? [:]

    let toolName: String
    let toolInput: JSONValue
    let body: ToolBody
    switch callName {
    case commandTool:
      guard let command = arguments["CommandLine"]?.stringValue else {
        throw AdapterError.malformedInput("missing CommandLine")
      }
      toolName = callName
      toolInput = .object(arguments)
      body = .bash(command: command, description: summary(in: arguments))
    case mcpTool:
      guard let mcpToolName = arguments["ToolName"]?.stringValue else {
        throw AdapterError.malformedInput("missing ToolName")
      }
      toolName = mcpToolName
      toolInput = arguments["Arguments"] ?? .object([:])
      body = .mcp(
        server: arguments["ServerName"]?.stringValue ?? "", tool: mcpToolName, arguments: toolInput)
    default:
      toolName = callName
      toolInput = .object(arguments)
      body = .json(toolInput)
    }

    return ApprovalRequest(
      host: .antigravity,
      sessionID: sessionID,
      cwd: workingDirectory(in: root, arguments: arguments),
      permissionMode: nil,
      transcriptPath: root["transcriptPath"]?.stringValue,
      agentID: nil,
      agentType: nil,
      toolName: toolName,
      toolInput: toolInput,
      kind: .permission(PermissionPrompt(body: body, suggestions: [])),
      isAskedAbout: askedTools.contains(callName)
    )
  }

  public static func encode(_ outcome: ApprovalOutcome) -> Data? {
    switch outcome {
    case .addContext:
      return nil
    case .noDecision:
      return encodeReply(["decision": .string("ask")])
    case .allow:
      return encodeReply(["decision": .string("allow")])
    case .deny(let message, _):
      return encodeReply(["decision": .string("deny"), "reason": .string(message)])
    }
  }

  private static func workingDirectory(
    in root: [String: JSONValue], arguments: [String: JSONValue]
  ) -> String {
    if let firstPath = root["workspacePaths"]?.arrayValue?.first?.stringValue, !firstPath.isEmpty {
      return firstPath
    }
    return arguments["Cwd"]?.stringValue ?? ""
  }

  private static func summary(in arguments: [String: JSONValue]) -> String? {
    guard let summary = arguments["toolSummary"]?.stringValue, !summary.isEmpty else { return nil }
    return summary
  }

  private static func encodeReply(_ reply: [String: JSONValue]) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try? encoder.encode(JSONValue.object(reply))
  }
}
