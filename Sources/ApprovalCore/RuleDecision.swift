import Foundation

public enum RuleDecision: Sendable, Equatable {
  case allow(ruleIndex: Int)
  case deny(message: String, ruleIndex: Int)
}

public enum RuleEvaluator {
  public static func decide(
    _ request: ApprovalRequest, rules: [ApprovalRule], home: URL
  ) -> RuleDecision? {
    guard case .permission(let prompt) = request.kind else { return nil }
    let command = bashCommand(prompt.body)
    let segments = command.flatMap { ShellCommandSegments.split($0) }
    let scoped = rules.enumerated().filter { _, rule in
      isInScope(rule, request: request, hasCommand: command != nil, home: home)
    }

    for (index, rule) in scoped where rule.decision == .deny {
      guard let pattern = rule.command else {
        return .deny(message: denyMessage(rule), ruleIndex: index)
      }
      if let segments, segments.contains(where: { CommandPattern(pattern).matches($0) }) {
        return .deny(message: denyMessage(rule), ruleIndex: index)
      }
    }

    let allows = scoped.filter { $0.element.decision == .allow }
    if let outright = allows.first(where: { $0.element.command == nil }) {
      return .allow(ruleIndex: outright.offset)
    }

    guard let segments, !segments.isEmpty else { return nil }
    var firstMatchIndex: Int?
    for segment in segments {
      guard
        let match = allows.first(where: { _, rule in
          rule.command.map { CommandPattern($0).matches(segment) } ?? false
        })
      else { return nil }
      if firstMatchIndex == nil { firstMatchIndex = match.offset }
    }
    return firstMatchIndex.map { .allow(ruleIndex: $0) }
  }

  private static func bashCommand(_ body: ToolBody) -> String? {
    guard case .bash(let command, _) = body else { return nil }
    return command
  }

  private static func denyMessage(_ rule: ApprovalRule) -> String {
    rule.message ?? ApprovalRule.defaultDenyMessage
  }

  private static func isInScope(
    _ rule: ApprovalRule, request: ApprovalRequest, hasCommand: Bool, home: URL
  ) -> Bool {
    if let agent = rule.agent, agent != request.host { return false }
    if let project = rule.project, !contains(project: project, cwd: request.cwd, home: home) {
      return false
    }
    if let tool = rule.tool,
      !CommandPattern.globMatches(Array(tool), Array(request.toolName))
    {
      return false
    }
    if rule.command != nil, !hasCommand { return false }
    return true
  }

  private static func contains(project: String, cwd: String, home: URL) -> Bool {
    let root = withoutTrailingSlashes(expandingHome(project, home: home))
    let path = withoutTrailingSlashes(cwd)
    if root.isEmpty { return path.hasPrefix("/") || path.isEmpty }
    return path == root || path.hasPrefix(root + "/")
  }

  private static func expandingHome(_ path: String, home: URL) -> String {
    if path == "~" { return home.path }
    if path.hasPrefix("~/") { return home.path + String(path.dropFirst()) }
    return path
  }

  private static func withoutTrailingSlashes(_ path: String) -> String {
    var trimmed = Substring(path)
    while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
    return String(trimmed)
  }
}
