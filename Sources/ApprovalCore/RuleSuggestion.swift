import Foundation

public struct RuleSuggestion: Sendable, Equatable, Identifiable {
  public let id: String
  public let title: String
  public let summary: String
  public let rules: [ApprovalRule]

  public static let all: [RuleSuggestion] = [
    RuleSuggestion(
      id: "deny-rm-rf",
      title: "Deny rm -rf",
      summary: "Recursive force deletes, written rm -rf or rm -fr.",
      rules: denyRules(
        ["rm -rf", "rm -fr"],
        message:
          "Countersign denies rm -rf. Remove specific files instead, or ask the user to run it."
      )),
    RuleSuggestion(
      id: "deny-git-rewrites",
      title: "Deny git history rewrites",
      summary: "Force pushes, hard resets and git clean.",
      rules: denyRules(
        ["git:push*--force*", "git:push* -f*", "git:reset*--hard*", "git clean"],
        message: "Countersign denies rewriting git history and git clean. Ask the user to run it.")),
    RuleSuggestion(
      id: "deny-sudo",
      title: "Deny sudo",
      summary: "Commands that run as root.",
      rules: denyRules(["sudo"], message: "Countersign denies sudo. Ask the user to run it.")),
    RuleSuggestion(
      id: "allow-read-only-git",
      title: "Allow read-only git",
      summary: "git status, diff, log and show run without a panel.",
      rules: ["git status", "git diff", "git log", "git show"].map {
        ApprovalRule(decision: .allow, command: $0)
      }),
  ]

  public func missingRules(in existing: [ApprovalRule]) -> [ApprovalRule] {
    rules.filter { suggested in
      !existing.contains { Self.sameTarget($0, suggested) }
    }
  }

  public static func offered(given existing: [ApprovalRule]) -> [RuleSuggestion] {
    all.filter { !$0.missingRules(in: existing).isEmpty }
  }

  private static func denyRules(_ commands: [String], message: String) -> [ApprovalRule] {
    commands.map { ApprovalRule(decision: .deny, command: $0, message: message) }
  }

  private static func sameTarget(_ first: ApprovalRule, _ second: ApprovalRule) -> Bool {
    first.decision == second.decision && first.agent == second.agent
      && first.project == second.project && first.tool == second.tool
      && first.command == second.command
  }
}
