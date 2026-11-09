import Testing

@testable import ApprovalCore

@Suite struct RulesCommandLineTests {
  @Test func listParses() {
    #expect(RulesCommandLine.parse(["list"]) == .list)
  }

  @Test func denyWithAToolGivesADenyDraftForThatTool() {
    var expected = RuleDraft()
    expected.decision = .deny
    expected.tool = "Bash"
    #expect(RulesCommandLine.parse(["deny", "--tool", "Bash"]) == .deny(expected))
  }

  @Test func allFiveFlagsLandInTheirFieldsInAnyOrder() {
    let parsed = RulesCommandLine.parse([
      "deny", "--message", "No pushes.", "--command", "git push", "--agent", "claude",
      "--tool", "Bash", "--project", "~/code/shop",
    ])
    var expected = RuleDraft()
    expected.decision = .deny
    expected.agent = .claude
    expected.project = "~/code/shop"
    expected.tool = "Bash"
    expected.command = "git push"
    expected.message = "No pushes."
    #expect(parsed == .deny(expected))
  }

  @Test func everythingElseIsRejected() {
    let rejected = [
      [], ["bogus"], ["allow", "--tool", "Bash"], ["list", "x"], ["deny", "--allow"],
      ["deny", "--decision", "allow"], ["deny", "--tool"], ["deny", "--tool", "a", "--tool", "b"],
      ["deny", "--agent", "nope"], ["deny", "--tool", "  "],
    ]
    for arguments in rejected {
      #expect(RulesCommandLine.parse(arguments) == nil)
    }
  }

  @Test func denyRuleForcesTheDenyDecision() {
    var draft = RuleDraft()
    draft.decision = .allow
    draft.tool = "Bash"
    #expect(RulesCommandLine.denyRule(draft)?.decision == .deny)
  }

  @Test func denyRuleRefusesARelativeProject() {
    var draft = RuleDraft()
    draft.project = "shop"
    #expect(RulesCommandLine.denyRule(draft) == nil)
  }

  @Test func aScopeIsNeededUnlessAgentProjectToolOrCommandIsSet() {
    var message = RuleDraft()
    message.message = "x"
    #expect(RulesCommandLine.needsScope(RuleDraft()))
    #expect(RulesCommandLine.needsScope(message))

    var agent = RuleDraft()
    agent.agent = .codex
    var project = RuleDraft()
    project.project = "/tmp"
    var tool = RuleDraft()
    tool.tool = "Bash"
    var command = RuleDraft()
    command.command = "ls"
    for draft in [agent, project, tool, command] {
      #expect(!RulesCommandLine.needsScope(draft))
    }
  }

  @Test func descriptionNamesEverySetFieldInOrder() {
    let rule = ApprovalRule(
      decision: .deny, agent: .claude, project: "~/code/shop", tool: "Bash",
      command: "git push", message: "No pushes.")
    #expect(
      RulesCommandLine.description(of: rule)
        == "deny agent=claude project=\"~/code/shop\" tool=\"Bash\" command=\"git push\" message=\"No pushes.\""
    )
  }

  @Test func aRuleWithoutScopeIsMarkedAsEveryRequest() {
    #expect(
      RulesCommandLine.description(of: ApprovalRule(decision: .deny)) == "deny (every request)")
    #expect(
      RulesCommandLine.description(of: ApprovalRule(decision: .deny, message: "x"))
        == "deny (every request) message=\"x\"")
  }

  @Test func unreadableCountSkipsDenyOnlyNoticesAndOtherKeys() {
    let lines = [
      "rules[0]: unknown key",
      "rules[1].message: only used by deny rules, ignored",
      "idleSeconds: bad",
    ]
    #expect(ApprovalRule.unreadableCount(in: lines) == 1)
  }
}
