import Foundation

public struct RuleDraft: Sendable, Equatable {
  public var decision: ApprovalRule.Decision
  public var agent: Host?
  public var project: String
  public var tool: String
  public var command: String
  public var message: String

  public init() {
    decision = .allow
    agent = nil
    project = ""
    tool = ""
    command = ""
    message = ""
  }

  public init(rule: ApprovalRule) {
    decision = rule.decision
    agent = rule.agent
    project = rule.project ?? ""
    tool = rule.tool ?? ""
    command = rule.command ?? ""
    message = rule.message ?? ""
  }

  public var problems: [String] {
    var found: [String] = []
    let trimmedProject = Self.trimmed(project)
    if !trimmedProject.isEmpty, !(trimmedProject.hasPrefix("/") || trimmedProject.hasPrefix("~")) {
      found.append("The project must be a full path, or start with ~.")
    }
    let trimmedCommand = Self.trimmed(command)
    if !trimmedCommand.isEmpty {
      let parts = ShellCommandSegments.split(trimmedCommand)
      if parts == nil || (parts?.count ?? 0) > 1 {
        found.append(
          "Use one command per rule; a rule matches each part of a compound command on its own.")
      }
    }
    return found
  }

  public var broadAllowWarning: String? {
    guard decision == .allow, agent == nil, Self.trimmed(project).isEmpty,
      Self.trimmed(tool).isEmpty, Self.trimmed(command).isEmpty
    else { return nil }
    return "This allows every request from every agent."
  }

  public func rule() -> ApprovalRule? {
    guard problems.isEmpty else { return nil }
    return ApprovalRule(
      decision: decision,
      agent: agent,
      project: Self.optional(project),
      tool: Self.optional(tool),
      command: Self.optional(command),
      message: decision == .deny ? Self.optional(message) : nil)
  }

  private static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func optional(_ text: String) -> String? {
    let value = trimmed(text)
    return value.isEmpty ? nil : value
  }
}
