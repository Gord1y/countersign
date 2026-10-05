import Foundation
import Testing

@testable import ApprovalCore

@Suite struct RuleEvaluatorTests {
  private let home = URL(fileURLWithPath: "/Users/tester")

  private func request(
    _ fixture: String, host: ApprovalCore.Host, cwd: String? = nil, command: String? = nil
  ) throws -> ApprovalRequest {
    var request = try host.parse(FixtureLoader.data(fixture))
    if let cwd { request.cwd = cwd }
    if let command {
      request.kind = .permission(
        PermissionPrompt(body: .bash(command: command, description: nil), suggestions: []))
    }
    return request
  }

  private func shell(_ command: String, cwd: String? = nil, host: ApprovalCore.Host = .cursor)
    throws
    -> ApprovalRequest
  {
    try request(
      host == .cursor ? "cursor-shell" : "claude-bash", host: host, cwd: cwd, command: command)
  }

  private func decide(_ request: ApprovalRequest, _ rules: [ApprovalRule]) -> RuleDecision? {
    RuleEvaluator.decide(request, rules: rules, home: home)
  }

  @Test func noRulesDecideNothing() throws {
    #expect(decide(try shell("ls"), []) == nil)
  }

  @Test func agentScopeMatchesOnlyThatHost() throws {
    let rules = [ApprovalRule(decision: .allow, agent: .cursor)]
    #expect(decide(try shell("ls"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("ls", host: .claude), rules) == nil)
  }

  @Test func projectScopeCoversTheFolderAndItsChildren() throws {
    let rules = [ApprovalRule(decision: .allow, project: "/a/b")]
    #expect(decide(try shell("ls", cwd: "/a/b"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("ls", cwd: "/a/b/c"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("ls", cwd: "/a/bc"), rules) == nil)
    #expect(decide(try shell("ls", cwd: "/a"), rules) == nil)
  }

  @Test func projectScopeIgnoresTrailingSlashes() throws {
    let rules = [ApprovalRule(decision: .allow, project: "/a/b/")]
    #expect(decide(try shell("ls", cwd: "/a/b"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("ls", cwd: "/a/b/c/"), rules) == .allow(ruleIndex: 0))
    let plain = [ApprovalRule(decision: .allow, project: "/a/b")]
    #expect(decide(try shell("ls", cwd: "/a/b/"), plain) == .allow(ruleIndex: 0))
  }

  @Test func projectScopeExpandsTheHomeFolder() throws {
    let rules = [ApprovalRule(decision: .allow, project: "~/code/shop")]
    #expect(
      decide(try shell("ls", cwd: "/Users/tester/code/shop/app"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("ls", cwd: "/Users/other/code/shop"), rules) == nil)
    let wholeHome = [ApprovalRule(decision: .allow, project: "~")]
    #expect(decide(try shell("ls", cwd: "/Users/tester/x"), wholeHome) == .allow(ruleIndex: 0))
    #expect(decide(try shell("ls", cwd: "/Users/testers"), wholeHome) == nil)
  }

  @Test func toolGlobMatchesTheWholeNameCaseSensitively() throws {
    let bash = try request("claude-bash", host: .claude)
    let mcp = try request("claude-mcp", host: .claude)
    let patch = try request("codex-apply-patch", host: .codex)
    #expect(decide(bash, [ApprovalRule(decision: .allow, tool: "Bash")]) == .allow(ruleIndex: 0))
    #expect(decide(bash, [ApprovalRule(decision: .allow, tool: "bash")]) == nil)
    #expect(decide(bash, [ApprovalRule(decision: .allow, tool: "Bas")]) == nil)
    #expect(decide(mcp, [ApprovalRule(decision: .allow, tool: "mcp__*")]) == .allow(ruleIndex: 0))
    #expect(decide(bash, [ApprovalRule(decision: .allow, tool: "mcp__*")]) == nil)
    #expect(
      decide(patch, [ApprovalRule(decision: .allow, tool: "apply_patch")]) == .allow(ruleIndex: 0))
    #expect(decide(patch, [ApprovalRule(decision: .allow, tool: "Bash")]) == nil)
  }

  @Test func allowWithACommandDecidesASingleCommand() throws {
    let rules = [ApprovalRule(decision: .allow, command: "pnpm lint")]
    #expect(decide(try shell("pnpm lint"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("pnpm lint --fix"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("pnpm install"), rules) == nil)
  }

  @Test func aCompoundCommandIsAllowedOnlyWhenEveryPartIs() throws {
    let rules = [
      ApprovalRule(decision: .allow, command: "pnpm lint"),
      ApprovalRule(decision: .allow, command: "cd"),
    ]
    #expect(decide(try shell("cd x && pnpm lint"), rules) == .allow(ruleIndex: 1))
    #expect(decide(try shell("pnpm lint && cd x"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("cd x && pnpm lint && rm y"), rules) == nil)
  }

  @Test func denyAppliesToAnySegment() throws {
    let rules = [ApprovalRule(decision: .deny, command: "rm")]
    #expect(
      decide(try shell("ls && rm -rf x"), rules)
        == .deny(message: ApprovalRule.defaultDenyMessage, ruleIndex: 0))
    #expect(decide(try shell("ls"), rules) == nil)
  }

  @Test func denyBeatsAnAllowThatAlsoMatches() throws {
    let rules = [
      ApprovalRule(decision: .allow),
      ApprovalRule(decision: .allow, command: "rm"),
      ApprovalRule(decision: .deny, command: "rm", message: "No rm."),
    ]
    #expect(decide(try shell("rm x"), rules) == .deny(message: "No rm.", ruleIndex: 2))
  }

  @Test func theFirstApplyingDenyRuleSuppliesTheMessage() throws {
    let rules = [
      ApprovalRule(decision: .deny, command: "git push", message: "First."),
      ApprovalRule(decision: .deny, command: "git", message: "Second."),
    ]
    #expect(decide(try shell("git push"), rules) == .deny(message: "First.", ruleIndex: 0))
    #expect(decide(try shell("git pull"), rules) == .deny(message: "Second.", ruleIndex: 1))
  }

  @Test func denyWithoutACommandBlocksEverythingInScope() throws {
    let rules = [ApprovalRule(decision: .deny, agent: .codex, tool: "apply_patch")]
    let patch = try request("codex-apply-patch", host: .codex)
    #expect(
      decide(patch, rules) == .deny(message: ApprovalRule.defaultDenyMessage, ruleIndex: 0))
    #expect(decide(try shell("ls"), rules) == nil)
  }

  @Test func allowWithoutACommandDecidesAnyToolInScope() throws {
    let rules = [ApprovalRule(decision: .allow, agent: .codex)]
    #expect(
      decide(try request("codex-apply-patch", host: .codex), rules) == .allow(ruleIndex: 0))
    #expect(decide(try request("claude-mcp", host: .claude), rules) == nil)
  }

  @Test func aCommandRuleIsOutOfScopeForANonShellRequest() throws {
    let rules = [
      ApprovalRule(decision: .deny, command: "rm"),
      ApprovalRule(decision: .allow, command: "ls"),
    ]
    #expect(decide(try request("claude-mcp", host: .claude), rules) == nil)
    #expect(decide(try request("codex-apply-patch", host: .codex), rules) == nil)
  }

  @Test func anUnsplittableCommandIsNeverDecidedByACommandRule() throws {
    let rules = [
      ApprovalRule(decision: .allow, command: "echo"),
      ApprovalRule(decision: .deny, command: "rm"),
    ]
    #expect(decide(try shell("echo $(rm x)"), rules) == nil)
  }

  @Test func aCommentOrAnExpansionNeverHidesASecondCommandFromAnAllowRule() throws {
    let rules = [ApprovalRule(decision: .allow, command: "git log")]
    #expect(decide(try shell("git log # '\nrm -rf x\n#'"), rules) == nil)
    #expect(decide(try shell("git log $'\\'' ; rm -rf x\n'"), rules) == nil)
    #expect(decide(try shell("git log \"${(e)${:-\\$(rm -rf x)}}\""), rules) == nil)
  }

  @Test func anUnsplittableCommandIsStillDecidedByARuleWithoutACommand() throws {
    let allow = [ApprovalRule(decision: .allow, agent: .cursor)]
    #expect(decide(try shell("echo $(rm x)"), allow) == .allow(ruleIndex: 0))
    let deny = [ApprovalRule(decision: .deny, agent: .cursor, message: "Stop.")]
    #expect(decide(try shell("echo $(rm x)"), deny) == .deny(message: "Stop.", ruleIndex: 0))
  }

  @Test func aRuleOutsideTheScopeNeverDecidesEvenWithAMatchingCommand() throws {
    let rules = [
      ApprovalRule(decision: .deny, agent: .claude, command: "rm"),
      ApprovalRule(decision: .allow, agent: .cursor, project: "/other", command: "rm"),
    ]
    #expect(decide(try shell("rm x", cwd: "/a"), rules) == nil)
  }

  @Test func ruleIndexesAreThePositionsInTheGivenList() throws {
    let rules = [
      ApprovalRule(decision: .allow, command: "ls"),
      ApprovalRule(decision: .allow, command: "pwd"),
      ApprovalRule(decision: .deny, command: "rm"),
    ]
    #expect(decide(try shell("pwd"), rules) == .allow(ruleIndex: 1))
    #expect(decide(try shell("ls && pwd"), rules) == .allow(ruleIndex: 0))
    #expect(decide(try shell("pwd && ls"), rules) == .allow(ruleIndex: 1))
    #expect(
      decide(try shell("rm x"), rules)
        == .deny(message: ApprovalRule.defaultDenyMessage, ruleIndex: 2))
  }

  @Test func onlyPermissionRequestsAreDecided() throws {
    var checkpoint = try shell("ls")
    checkpoint.kind = .questions([])
    #expect(decide(checkpoint, [ApprovalRule(decision: .allow)]) == nil)
  }
}
