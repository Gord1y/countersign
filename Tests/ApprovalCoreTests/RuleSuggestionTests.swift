import Foundation
import Testing

@testable import ApprovalCore

private func editing(_ text: String?, _ edits: PreferenceEdit...) throws -> String {
  let bytes = try ConfigEdit.applying(edits, to: text.map { Array($0.utf8) })
  return String(decoding: bytes, as: UTF8.self)
}

@Suite struct RuleSuggestionTests {
  private let home = URL(fileURLWithPath: "/Users/tester")

  private func suggestion(_ id: String) throws -> RuleSuggestion {
    try #require(RuleSuggestion.all.first { $0.id == id })
  }

  private func shell(_ command: String) throws -> ApprovalRequest {
    var request = try ApprovalCore.Host.cursor.parse(FixtureLoader.data("cursor-shell"))
    request.kind = .permission(
      PermissionPrompt(body: .bash(command: command, description: nil), suggestions: []))
    return request
  }

  private func decision(_ id: String, _ command: String) throws -> ApprovalRule.Decision? {
    let outcome = try RuleEvaluator.decide(
      shell(command), rules: suggestion(id).rules, home: home)
    switch outcome {
    case .allow: return .allow
    case .deny: return .deny
    case nil: return nil
    }
  }

  @Test func allListsTheCardsInOrder() {
    #expect(
      RuleSuggestion.all.map(\.id) == [
        "deny-rm-rf", "deny-git-rewrites", "deny-sudo", "allow-read-only-git",
      ])
  }

  @Test(arguments: RuleSuggestion.all)
  func everyRuleSurvivesAWriteAndARead(suggestion: RuleSuggestion) throws {
    for start in [nil, "{}"] {
      let text = try editing(start, .addRules(suggestion.rules))
      let (file, logLines) = ConfigFileParser.parse(Data(text.utf8))
      #expect(file.rules == suggestion.rules)
      #expect(logLines.isEmpty)
    }
  }

  @Test(arguments: RuleSuggestion.all)
  func everyRulePassesTheForm(suggestion: RuleSuggestion) {
    for rule in suggestion.rules {
      let draft = RuleDraft(rule: rule)
      #expect(draft.problems.isEmpty)
      #expect(draft.rule() == rule)
    }
  }

  @Test func rmRfDeniesBothSpellings() throws {
    #expect(try decision("deny-rm-rf", "rm -rf build") == .deny)
    #expect(try decision("deny-rm-rf", "rm -fr /tmp/x") == .deny)
    #expect(try decision("deny-rm-rf", "rm file.txt") == nil)
  }

  @Test func gitRewritesDenyForcePushesResetsAndClean() throws {
    for command in [
      "git push --force", "git push origin main --force-with-lease", "git push -f origin",
      "git reset --hard HEAD~1", "git reset HEAD~1 --hard", "git clean -fdx",
    ] {
      #expect(try decision("deny-git-rewrites", command) == .deny, "\(command)")
    }
    for command in ["git push origin main", "git push --follow-tags", "git reset HEAD file"] {
      #expect(try decision("deny-git-rewrites", command) == nil, "\(command)")
    }
  }

  @Test func sudoDeniesOnlyTheCommand() throws {
    #expect(try decision("deny-sudo", "sudo rm x") == .deny)
    #expect(try decision("deny-sudo", "echo sudo") == nil)
  }

  @Test func readOnlyGitAllowsEveryPartOnly() throws {
    #expect(try decision("allow-read-only-git", "git status --short") == .allow)
    #expect(try decision("allow-read-only-git", "git diff HEAD && git log -1 --oneline") == .allow)
    #expect(try decision("allow-read-only-git", "git status && git push") == nil)
  }

  @Test func missingRulesIgnoresTheMessageButNotTheScope() throws {
    let rmRf = try suggestion("deny-rm-rf")
    let first = rmRf.rules[0]
    let second = rmRf.rules[1]
    #expect(rmRf.missingRules(in: []) == rmRf.rules)
    #expect(rmRf.missingRules(in: [first]) == [second])
    #expect(rmRf.missingRules(in: [first, second]).isEmpty)
    #expect(
      rmRf.missingRules(in: [ApprovalRule(decision: .deny, command: "rm -rf", message: "mine")])
        == [second])
    #expect(rmRf.missingRules(in: [ApprovalRule(decision: .deny, command: "rm -rf")]) == [second])
    let scoped = ApprovalRule(decision: .deny, project: "/work/shop", command: "rm -rf")
    #expect(rmRf.missingRules(in: [scoped]) == rmRf.rules)
  }

  @Test func offeredDropsTheCardsWithNothingMissing() throws {
    #expect(RuleSuggestion.offered(given: []) == RuleSuggestion.all)
    let sudo = try suggestion("deny-sudo")
    #expect(
      RuleSuggestion.offered(given: sudo.rules).map(\.id) == [
        "deny-rm-rf", "deny-git-rewrites", "allow-read-only-git",
      ])
  }
}
