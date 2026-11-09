import Foundation

public enum RulesCommandLine: Sendable, Equatable {
  case list
  case deny(RuleDraft)

  public static let usage = """
    usage: countersign rules list
           countersign rules deny [--agent <agent>] [--project <folder>] [--tool <name>] [--command <pattern>] [--message <text>]
           <agent> is claude, codex, cursor or antigravity
    """
  public static let noScope =
    "error: a deny rule needs --agent, --project, --tool or --command; without one it would block every request"
  public static let empty = "no rules"

  public static func parse(_ arguments: [String]) -> RulesCommandLine? {
    guard let subcommand = arguments.first else { return nil }
    let rest = Array(arguments.dropFirst())
    switch subcommand {
    case "list":
      return rest.isEmpty ? .list : nil
    case "deny":
      return parseDeny(rest)
    default:
      return nil
    }
  }

  public static func needsScope(_ draft: RuleDraft) -> Bool {
    draft.agent == nil && [draft.project, draft.tool, draft.command].allSatisfy { isBlank($0) }
  }

  public static func denyRule(_ draft: RuleDraft) -> ApprovalRule? {
    var denying = draft
    denying.decision = .deny
    return denying.rule()
  }

  public static func description(of rule: ApprovalRule) -> String {
    var text = rule.decision.rawValue
    if let agent = rule.agent { text += " agent=\(agent.rawValue)" }
    if let project = rule.project { text += " project=\"\(project)\"" }
    if let tool = rule.tool { text += " tool=\"\(tool)\"" }
    if let command = rule.command { text += " command=\"\(command)\"" }
    if rule.agent == nil, rule.project == nil, rule.tool == nil, rule.command == nil {
      text += " (every request)"
    }
    if let message = rule.message { text += " message=\"\(message)\"" }
    return text
  }

  public static func row(index: Int, rule: ApprovalRule) -> String {
    "rules[\(index)]  \(description(of: rule))"
  }

  public static func added(_ rule: ApprovalRule) -> String {
    "added: \(description(of: rule))"
  }

  public static func alreadyThere(_ rule: ApprovalRule) -> String {
    "already there: \(description(of: rule))"
  }

  public static func unreadableNotice(count: Int) -> String {
    if count == 1 {
      return "1 entry in rules could not be read and does nothing; fix it in config.json"
    }
    return "\(count) entries in rules could not be read and do nothing; fix them in config.json"
  }

  private static func parseDeny(_ arguments: [String]) -> RulesCommandLine? {
    guard arguments.count.isMultiple(of: 2) else { return nil }
    var draft = RuleDraft()
    draft.decision = .deny
    var seen: Set<String> = []
    var index = 0
    while index < arguments.count {
      let flag = arguments[index]
      let value = arguments[index + 1]
      index += 2
      guard seen.insert(flag).inserted, !isBlank(value) else { return nil }
      switch flag {
      case "--agent":
        guard let agent = Host(rawValue: value) else { return nil }
        draft.agent = agent
      case "--project": draft.project = value
      case "--tool": draft.tool = value
      case "--command": draft.command = value
      case "--message": draft.message = value
      default: return nil
      }
    }
    return .deny(draft)
  }

  private static func isBlank(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
