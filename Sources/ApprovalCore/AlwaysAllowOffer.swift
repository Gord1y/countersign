import Foundation

public struct AlwaysAllowOffer: Sendable, Equatable {
  public let rules: [ApprovalRule]
  public let title: String
  public let detail: String

  public static func offer(for request: ApprovalRequest, home: URL) -> AlwaysAllowOffer? {
    guard request.host != .claude, request.host.honorsHookAllow, !request.cwd.isEmpty,
      case .permission(let prompt) = request.kind
    else { return nil }
    let project = HomePath.abbreviating(request.cwd, relativeTo: home)
    let scope = ApprovalRule(decision: .allow, agent: request.host, project: project)
    let place = "\(request.host.displayName) in \(request.projectName)"

    if case .bash(let command, _) = prompt.body {
      guard let patterns = distinctPatterns(of: command) else { return nil }
      let rules = patterns.map { pattern -> ApprovalRule in
        var rule = scope
        rule.command = pattern
        return rule
      }
      if let only = patterns.first, patterns.count == 1 {
        return AlwaysAllowOffer(
          rules: rules, title: "Always allow \"\(only)\"", detail: place)
      }
      return AlwaysAllowOffer(
        rules: rules, title: "Always allow these \(patterns.count) commands",
        detail: place + ": " + patterns.joined(separator: ", "))
    }

    var rule = scope
    rule.tool = request.toolName
    return AlwaysAllowOffer(
      rules: [rule], title: "Always allow \(request.toolName)", detail: place)
  }

  private static func distinctPatterns(of command: String) -> [String]? {
    guard let segments = ShellCommandSegments.split(command), !segments.isEmpty else {
      return nil
    }
    var patterns: [String] = []
    for segment in segments {
      guard let pattern = CommandPattern.exact(forSegment: segment) else { return nil }
      if !patterns.contains(pattern.text) {
        patterns.append(pattern.text)
      }
    }
    return patterns
  }
}
