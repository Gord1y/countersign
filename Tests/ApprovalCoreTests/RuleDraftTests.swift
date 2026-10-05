import Testing

@testable import ApprovalCore

@Suite struct RuleDraftTests {
  @Test func roundTripsEveryFieldSet() {
    let rules = [
      ApprovalRule(
        decision: .deny, agent: .cursor, project: "~/code/app", tool: "Shell",
        command: "rm:*", message: "No."),
      ApprovalRule(
        decision: .allow, agent: .codex, project: "/tmp/x", tool: "Bash", command: "git"),
      ApprovalRule(decision: .allow, tool: "mcp__github__*"),
      ApprovalRule(decision: .deny),
    ]
    for rule in rules {
      #expect(RuleDraft(rule: rule).rule() == rule)
    }
  }

  @Test func emptyFieldsMeanAny() {
    var draft = RuleDraft()
    draft.project = "  "
    draft.tool = ""
    draft.command = " \n"
    #expect(draft.rule() == ApprovalRule(decision: .allow))
  }

  @Test func relativeProjectIsAProblem() {
    var draft = RuleDraft()
    draft.project = "code/app"
    #expect(draft.problems == ["The project must be a full path, or start with ~."])
    #expect(draft.rule() == nil)
  }

  @Test func compoundCommandIsAProblem() {
    var draft = RuleDraft()
    draft.command = "git status && git diff"
    #expect(
      draft.problems == [
        "Use one command per rule; a rule matches each part of a compound command on its own."
      ])
    #expect(draft.rule() == nil)
  }

  @Test func unreadableCommandIsAProblem() {
    var draft = RuleDraft()
    draft.command = "echo $(whoami)"
    #expect(draft.problems.count == 1)
    #expect(draft.rule() == nil)
  }

  @Test func messageIsDroppedForAllow() {
    var draft = RuleDraft()
    draft.tool = "Read"
    draft.message = "Nope."
    #expect(draft.rule()?.message == nil)
    draft.decision = .deny
    #expect(draft.rule()?.message == "Nope.")
  }

  @Test func broadAllowWarningOnlyForAnUnscopedAllow() {
    var draft = RuleDraft()
    #expect(draft.broadAllowWarning == "This allows every request from every agent.")
    draft.tool = "Read"
    #expect(draft.broadAllowWarning == nil)
    draft.tool = ""
    draft.agent = .claude
    #expect(draft.broadAllowWarning == nil)
    draft.agent = nil
    draft.decision = .deny
    #expect(draft.broadAllowWarning == nil)
  }
}
