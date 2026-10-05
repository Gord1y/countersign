import Foundation

public enum CodexAdapter {
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
    guard let sessionID = root["session_id"]?.stringValue else {
      throw AdapterError.malformedInput("missing session_id")
    }
    guard let cwd = root["cwd"]?.stringValue else {
      throw AdapterError.malformedInput("missing cwd")
    }
    guard let toolName = root["tool_name"]?.stringValue else {
      throw AdapterError.malformedInput("missing tool_name")
    }
    guard let toolInput = root["tool_input"], case .object(let toolInputObject) = toolInput else {
      throw AdapterError.malformedInput("missing tool_input")
    }
    if let hookEventName = root["hook_event_name"] {
      guard hookEventName.stringValue == "PermissionRequest" else {
        throw AdapterError.malformedInput("unexpected hook_event_name")
      }
    }

    let permissionMode = root["permission_mode"]?.stringValue
    let transcriptPath = root["transcript_path"]?.stringValue
    let agentID = root["agent_id"]?.stringValue
    let agentType = root["agent_type"]?.stringValue

    let body = permissionBody(
      toolName: toolName, toolInput: toolInput, toolInputObject: toolInputObject)
    let kind = RequestKind.permission(PermissionPrompt(body: body, suggestions: []))

    return ApprovalRequest(
      host: .codex,
      sessionID: sessionID,
      cwd: cwd,
      permissionMode: permissionMode,
      transcriptPath: transcriptPath,
      agentID: agentID,
      agentType: agentType,
      toolName: toolName,
      toolInput: toolInput,
      kind: kind
    )
  }

  public static func encode(_ outcome: ApprovalOutcome) -> Data? {
    switch outcome {
    case .noDecision, .addContext:
      return nil
    case .allow:
      return encodeEnvelope(["behavior": .string("allow")])
    case .deny(let message, _):
      return encodeEnvelope(["behavior": .string("deny"), "message": .string(message)])
    }
  }

  private static func permissionBody(
    toolName: String,
    toolInput: JSONValue,
    toolInputObject: [String: JSONValue]
  ) -> ToolBody {
    switch toolName {
    case "Bash":
      if let commandValue = toolInputObject["command"] {
        if let command = commandValue.stringValue {
          return .bash(command: command, description: nil)
        }
        if let elements = commandValue.arrayValue {
          let strings = elements.compactMap { $0.stringValue }
          if strings.count == elements.count {
            return .bash(command: argvCommand(strings), description: nil)
          }
        }
      }
    case "apply_patch", "Edit", "Write":
      if let commandValue = toolInputObject["command"] {
        if let command = commandValue.stringValue {
          return .patch(text: command)
        }
        if let elements = commandValue.arrayValue {
          let strings = elements.compactMap { $0.stringValue }
          if strings.count == elements.count {
            if let patch = strings.first(where: { $0.contains("*** Begin Patch") }) {
              return .patch(text: patch)
            }
            return .patch(text: strings.joined(separator: "\n"))
          }
        }
      }
    default:
      if toolName.hasPrefix("mcp__") {
        return mcpBody(toolName: toolName, toolInput: toolInput)
      }
    }
    return .json(toolInput)
  }

  private static func mcpBody(toolName: String, toolInput: JSONValue) -> ToolBody {
    let remainder = toolName.dropFirst("mcp__".count)
    guard let separatorRange = remainder.range(of: "__") else {
      return .mcp(server: String(remainder), tool: "", arguments: toolInput)
    }
    let server = String(remainder[..<separatorRange.lowerBound])
    let tool = String(remainder[separatorRange.upperBound...])
    return .mcp(server: server, tool: tool, arguments: toolInput)
  }

  private static func argvCommand(_ elements: [String]) -> String {
    if elements.count == 3 {
      let shellName = (elements[0] as NSString).lastPathComponent
      let allowedShells = ["bash", "sh", "zsh"]
      let allowedFlags = ["-c", "-lc"]
      if allowedShells.contains(shellName), allowedFlags.contains(elements[1]) {
        return elements[2]
      }
    }
    return elements.map(quoteArgvElement).joined(separator: " ")
  }

  private static func quoteArgvElement(_ element: String) -> String {
    let specialCharacters = Set("$`\\|&;<>()*?[]{}!#~'\"")
    let needsQuoting =
      element.isEmpty
      || element.contains(where: { $0.isWhitespace })
      || element.contains(where: { specialCharacters.contains($0) })
    guard needsQuoting else { return element }
    let escaped = element.replacingOccurrences(of: "'", with: "'\\''")
    return "'\(escaped)'"
  }

  private static func encodeEnvelope(_ decision: [String: JSONValue]) -> Data? {
    let envelope: JSONValue = .object([
      "hookSpecificOutput": .object([
        "hookEventName": .string("PermissionRequest"),
        "decision": .object(decision),
      ])
    ])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try? encoder.encode(envelope)
  }
}
