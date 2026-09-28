import Foundation

public enum AdapterError: Error, Equatable {
  case malformedInput(String)
}

public enum ClaudeAdapter {
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
    let mcpServer = root["mcp_server"]?.stringValue

    let kind: RequestKind
    switch toolName {
    case "AskUserQuestion":
      kind = .questions(try parseQuestions(toolInputObject))
    case "ExitPlanMode":
      kind = .plan(try parsePlan(toolInputObject))
    default:
      let body = permissionBody(
        toolName: toolName,
        toolInput: toolInput,
        toolInputObject: toolInputObject,
        mcpServer: mcpServer
      )
      let suggestions = parseSuggestions(root["permission_suggestions"])
      kind = .permission(PermissionPrompt(body: body, suggestions: suggestions))
    }

    return ApprovalRequest(
      host: .claude,
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
    case .noDecision:
      return nil
    case .allow(let updatedInput, let updatedPermissions):
      var decision: [String: JSONValue] = ["behavior": .string("allow")]
      if let updatedInput {
        decision["updatedInput"] = updatedInput
      }
      if !updatedPermissions.isEmpty {
        decision["updatedPermissions"] = .array(updatedPermissions)
      }
      return encodeEnvelope(decision)
    case .deny(let message, let interrupt):
      var decision: [String: JSONValue] = [
        "behavior": .string("deny"),
        "message": .string(message),
      ]
      if interrupt {
        decision["interrupt"] = .bool(true)
      }
      return encodeEnvelope(decision)
    }
  }

  private static func parseQuestions(_ toolInputObject: [String: JSONValue]) throws -> [Question] {
    guard let questionsArray = toolInputObject["questions"]?.arrayValue else {
      throw AdapterError.malformedInput("missing questions")
    }
    guard (1...4).contains(questionsArray.count) else {
      throw AdapterError.malformedInput("questions must contain 1 to 4 entries")
    }
    return try questionsArray.map(parseQuestion)
  }

  private static func parseQuestion(_ value: JSONValue) throws -> Question {
    guard case .object(let object) = value else {
      throw AdapterError.malformedInput("question is not an object")
    }
    guard let question = object["question"]?.stringValue else {
      throw AdapterError.malformedInput("missing question text")
    }
    guard let optionsArray = object["options"]?.arrayValue, !optionsArray.isEmpty else {
      throw AdapterError.malformedInput("missing options")
    }
    let options = try optionsArray.map(parseQuestionOption)
    let header = object["header"]?.stringValue
    let multiSelect = object["multiSelect"]?.boolValue ?? false
    return Question(question: question, header: header, options: options, multiSelect: multiSelect)
  }

  private static func parseQuestionOption(_ value: JSONValue) throws -> QuestionOption {
    guard case .object(let object) = value else {
      throw AdapterError.malformedInput("option is not an object")
    }
    guard let label = object["label"]?.stringValue else {
      throw AdapterError.malformedInput("missing option label")
    }
    let description = object["description"]?.stringValue
    let preview = object["preview"]?.stringValue
    return QuestionOption(label: label, description: description, preview: preview)
  }

  private static func parsePlan(_ toolInputObject: [String: JSONValue]) throws -> PlanProposal {
    guard let plan = toolInputObject["plan"]?.stringValue else {
      throw AdapterError.malformedInput("missing plan")
    }
    let planFilePath = toolInputObject["planFilePath"]?.stringValue
    return PlanProposal(plan: plan, planFilePath: planFilePath)
  }

  private static func permissionBody(
    toolName: String,
    toolInput: JSONValue,
    toolInputObject: [String: JSONValue],
    mcpServer: String?
  ) -> ToolBody {
    switch toolName {
    case "Bash":
      if let command = toolInputObject["command"]?.stringValue {
        return .bash(command: command, description: toolInputObject["description"]?.stringValue)
      }
    case "Edit":
      if let path = toolInputObject["file_path"]?.stringValue,
        let oldString = toolInputObject["old_string"]?.stringValue,
        let newString = toolInputObject["new_string"]?.stringValue
      {
        let replaceAll = toolInputObject["replace_all"]?.boolValue ?? false
        return .edit(path: path, oldString: oldString, newString: newString, replaceAll: replaceAll)
      }
    case "Write":
      if let path = toolInputObject["file_path"]?.stringValue,
        let content = toolInputObject["content"]?.stringValue
      {
        return .write(path: path, content: content)
      }
    case "WebFetch":
      if let url = toolInputObject["url"]?.stringValue {
        return .webFetch(url: url, prompt: toolInputObject["prompt"]?.stringValue)
      }
    default:
      if toolName.hasPrefix("mcp__") {
        return mcpBody(toolName: toolName, toolInput: toolInput, mcpServer: mcpServer)
      }
    }
    return .json(toolInput)
  }

  private static func mcpBody(toolName: String, toolInput: JSONValue, mcpServer: String?)
    -> ToolBody
  {
    let remainder = toolName.dropFirst("mcp__".count)
    guard let separatorRange = remainder.range(of: "__") else {
      return .mcp(server: mcpServer ?? String(remainder), tool: "", arguments: toolInput)
    }
    let serverSegment = String(remainder[..<separatorRange.lowerBound])
    let tool = String(remainder[separatorRange.upperBound...])
    return .mcp(server: mcpServer ?? serverSegment, tool: tool, arguments: toolInput)
  }

  private static func parseSuggestions(_ value: JSONValue?) -> [PermissionSuggestion] {
    guard let entries = value?.arrayValue else { return [] }
    return entries.compactMap { entry in
      guard case .object = entry else { return nil }
      return PermissionSuggestion(raw: entry, label: suggestionLabel(entry))
    }
  }

  private static func suggestionLabel(_ entry: JSONValue) -> String {
    guard case .object(let object) = entry else { return "" }
    let type = object["type"]?.stringValue ?? ""
    switch type {
    case "addRules", "replaceRules":
      let rules = object["rules"]?.arrayValue ?? []
      let ruleLabels = rules.compactMap { ruleValue -> String? in
        guard case .object(let ruleObject) = ruleValue,
          let toolName = ruleObject["toolName"]?.stringValue
        else { return nil }
        if let ruleContent = ruleObject["ruleContent"]?.stringValue {
          return "\(toolName)(\(ruleContent))"
        }
        return toolName
      }
      let behavior = object["behavior"]?.stringValue
      let prefix: String
      if let behavior, behavior != "allow" {
        prefix = "Always \(behavior)"
      } else {
        prefix = "Always allow"
      }
      return "\(prefix) \(ruleLabels.joined(separator: ", "))\(destinationSuffix(object))"
    case "setMode":
      let mode = object["mode"]?.stringValue ?? ""
      return "Allow and switch to \(mode)"
    case "addDirectories":
      let directories = object["directories"]?.arrayValue?.compactMap { $0.stringValue } ?? []
      return
        "Always allow access to \(directories.joined(separator: ", "))\(destinationSuffix(object))"
    default:
      return "Always allow (\(type))"
    }
  }

  private static func destinationSuffix(_ object: [String: JSONValue]) -> String {
    switch object["destination"]?.stringValue {
    case "localSettings": return " (this project, local)"
    case "projectSettings": return " (this project, shared)"
    case "userSettings": return " (all projects)"
    case "session": return " (this session)"
    default: return ""
    }
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
