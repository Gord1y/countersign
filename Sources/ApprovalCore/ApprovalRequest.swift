import Foundation

public enum Host: String, Sendable, Codable, CaseIterable {
  case claude
  case codex
  case cursor
  case antigravity

  public var displayName: String {
    switch self {
    case .claude: return "Claude Code"
    case .codex: return "Codex"
    case .cursor: return "Cursor"
    case .antigravity: return "Antigravity"
    }
  }

  public var supportsPermissionUpdates: Bool {
    self == .claude
  }

  public var supportsInterrupt: Bool {
    self == .claude
  }

  public var honorsHookAllow: Bool {
    switch self {
    case .claude, .codex: return true
    case .cursor, .antigravity: return false
    }
  }

  public var handoffOutcome: ApprovalOutcome? {
    switch self {
    case .claude, .codex: return nil
    case .cursor, .antigravity: return .noDecision
    }
  }

  public func parse(_ data: Data) throws -> ApprovalRequest {
    switch self {
    case .claude: return try ClaudeAdapter.parse(data)
    case .codex: return try CodexAdapter.parse(data)
    case .cursor: return try CursorAdapter.parse(data)
    case .antigravity: return try AntigravityAdapter.parse(data)
    }
  }

  public func encode(_ outcome: ApprovalOutcome) -> Data? {
    switch self {
    case .claude: return ClaudeAdapter.encode(outcome)
    case .codex: return CodexAdapter.encode(outcome)
    case .cursor: return CursorAdapter.encode(outcome)
    case .antigravity: return AntigravityAdapter.encode(outcome)
    }
  }
}

public struct ApprovalRequest: Sendable, Equatable {
  public var host: Host
  public var sessionID: String
  public var cwd: String
  public var permissionMode: String?
  public var transcriptPath: String?
  public var agentID: String?
  public var agentType: String?
  public var toolName: String
  public var toolInput: JSONValue
  public var kind: RequestKind
  public var runsInSandbox: Bool
  public var isAskedAbout: Bool

  public init(
    host: Host,
    sessionID: String,
    cwd: String,
    permissionMode: String?,
    transcriptPath: String?,
    agentID: String?,
    agentType: String?,
    toolName: String,
    toolInput: JSONValue,
    kind: RequestKind,
    runsInSandbox: Bool = false,
    isAskedAbout: Bool = true
  ) {
    self.host = host
    self.sessionID = sessionID
    self.cwd = cwd
    self.permissionMode = permissionMode
    self.transcriptPath = transcriptPath
    self.agentID = agentID
    self.agentType = agentType
    self.toolName = toolName
    self.toolInput = toolInput
    self.kind = kind
    self.runsInSandbox = runsInSandbox
    self.isAskedAbout = isAskedAbout
  }

  public var projectName: String {
    Self.projectName(cwd: cwd)
  }

  public static func projectName(cwd: String) -> String {
    let lastComponent = (cwd as NSString).lastPathComponent
    return lastComponent.isEmpty ? cwd : lastComponent
  }
}

public enum RequestKind: Sendable, Equatable {
  case permission(PermissionPrompt)
  case questions([Question])
  case plan(PlanProposal)
  case contextCheckpoint(ContextCheckpointPrompt)
}

extension ApprovalRequest {
  public static func contextCheckpoint(
    _ input: ContextCheckpointInput, prompt: ContextCheckpointPrompt
  ) -> ApprovalRequest {
    ApprovalRequest(
      host: .claude,
      sessionID: input.sessionID,
      cwd: input.cwd,
      permissionMode: input.permissionMode,
      transcriptPath: input.transcriptPath,
      agentID: nil,
      agentType: nil,
      toolName: "Context checkpoint",
      toolInput: .object([:]),
      kind: .contextCheckpoint(prompt)
    )
  }
}

public struct PermissionPrompt: Sendable, Equatable {
  public var body: ToolBody
  public var suggestions: [PermissionSuggestion]

  public init(body: ToolBody, suggestions: [PermissionSuggestion]) {
    self.body = body
    self.suggestions = suggestions
  }
}

public struct PermissionSuggestion: Sendable, Equatable {
  public var raw: JSONValue
  public var label: String

  public init(raw: JSONValue, label: String) {
    self.raw = raw
    self.label = label
  }
}

public enum ToolBody: Sendable, Equatable {
  case bash(command: String, description: String?)
  case edit(path: String, oldString: String, newString: String, replaceAll: Bool)
  case write(path: String, content: String)
  case patch(text: String)
  case webFetch(url: String, prompt: String?)
  case mcp(server: String, tool: String, arguments: JSONValue)
  case json(JSONValue)
}

public struct Question: Sendable, Equatable {
  public var question: String
  public var header: String?
  public var options: [QuestionOption]
  public var multiSelect: Bool

  public init(question: String, header: String?, options: [QuestionOption], multiSelect: Bool) {
    self.question = question
    self.header = header
    self.options = options
    self.multiSelect = multiSelect
  }
}

public struct QuestionOption: Sendable, Equatable {
  public var label: String
  public var description: String?
  public var preview: String?

  public init(label: String, description: String?, preview: String?) {
    self.label = label
    self.description = description
    self.preview = preview
  }
}

public struct PlanProposal: Sendable, Equatable {
  public var plan: String
  public var planFilePath: String?

  public init(plan: String, planFilePath: String?) {
    self.plan = plan
    self.planFilePath = planFilePath
  }
}
