import Testing

@testable import ApprovalCore

@Suite struct AgentFollowUpTests {
  @Test func claudeNeverGetsAFollowUp() {
    #expect(AgentFollowUps.current(host: .claude, wiringStatus: .wired) == nil)
  }

  @Test func codexGetsTheNextStepWhenWiredAndTrustIsUnknown() {
    let followUp = AgentFollowUps.current(host: .codex, wiringStatus: .wired, codexTrust: .unknown)
    #expect(followUp?.host == .codex)
    #expect(followUp?.kind == .nextStep)
    #expect(followUp?.text == AgentFollowUps.codexNextStep)
    #expect(followUp?.offersMarkAsDone == true)
  }

  @Test func codexGetsNoFollowUpOnceTrustedOrMarkedDone() {
    #expect(AgentFollowUps.current(host: .codex, wiringStatus: .wired, codexTrust: .trusted) == nil)
    #expect(
      AgentFollowUps.current(host: .codex, wiringStatus: .wired, codexTrust: .markedDone) == nil)
  }

  @Test func codexGetsTheNextStepWhilePending() {
    #expect(
      AgentFollowUps.current(
        host: .codex, wiringStatus: .wired,
        codexTrust: .pending(reason: nil, offersMarkAsDone: false))
        == AgentFollowUp(
          host: .codex, kind: .nextStep, text: AgentFollowUps.codexNextStep,
          offersMarkAsDone: false))
    #expect(
      AgentFollowUps.current(
        host: .codex, wiringStatus: .wired,
        codexTrust: .pending(
          reason: CodexTrustVerdict.hookAddedBeforeReason, offersMarkAsDone: true))
        == AgentFollowUp(
          host: .codex, kind: .nextStep,
          text:
            "Codex asks again because another hook was added before Countersign's. \(AgentFollowUps.codexNextStep)",
          offersMarkAsDone: true))
  }

  @Test func setupPrintsNothingForAnUninstallOrARunThatChangedNothing() {
    let wiring: [ApprovalCore.Host: HostWiringStatus] = [.codex: .wired, .cursor: .wired]
    #expect(
      AgentFollowUps.setupLines(
        wiring: wiring, codexTrust: .unknown, changedHosts: [.codex], uninstall: true) == [])
    #expect(
      AgentFollowUps.setupLines(
        wiring: wiring, codexTrust: .unknown, changedHosts: [], uninstall: false) == [])
  }

  @Test func setupPrintsCodexsNextStepWhateverTheRunChanged() {
    let wiring: [ApprovalCore.Host: HostWiringStatus] = [
      .claude: .wired, .codex: .wired, .cursor: .wired, .antigravity: .wired,
    ]
    #expect(
      AgentFollowUps.setupLines(
        wiring: wiring,
        codexTrust: .pending(
          reason: CodexTrustVerdict.hookRemovedBeforeReason, offersMarkAsDone: false),
        changedHosts: [.claude], uninstall: false)
        == [
          "Next step for Codex: Codex asks again because a hook before Countersign's was removed. \(AgentFollowUps.codexNextStep)"
        ])
    #expect(
      AgentFollowUps.setupLines(
        wiring: wiring, codexTrust: .trusted, changedHosts: [.claude], uninstall: false) == [])
  }

  @Test func setupPrintsGoodToKnowOnlyForTheHostsItChanged() {
    let wiring: [ApprovalCore.Host: HostWiringStatus] = [
      .codex: .wired, .cursor: .wired, .antigravity: .wired,
    ]
    #expect(
      AgentFollowUps.setupLines(
        wiring: wiring, codexTrust: .unknown, changedHosts: [.antigravity, .cursor],
        uninstall: false)
        == [
          "Next step for Codex: \(AgentFollowUps.codexNextStep)",
          "Good to know for Cursor: \(AgentFollowUps.cursorGoodToKnow)",
          "Good to know for Antigravity: \(AgentFollowUps.antigravityGoodToKnow)",
        ])
    #expect(
      AgentFollowUps.setupLines(
        wiring: [.cursor: .notWired, .antigravity: .wired], codexTrust: .unknown,
        changedHosts: [.cursor], uninstall: false) == [])
  }

  @Test func codexGetsNoFollowUpWhenNotWiredEvenIfTrustIsUnknown() {
    #expect(
      AgentFollowUps.current(host: .codex, wiringStatus: .notWired, codexTrust: .unknown) == nil)
    #expect(
      AgentFollowUps.current(
        host: .codex, wiringStatus: .needsUpdate(HostWiringUpdate(otherExecutablePaths: [])),
        codexTrust: .unknown) == nil)
  }

  @Test func cursorGetsAPermanentGoodToKnowLineWhenWired() {
    let followUp = AgentFollowUps.current(host: .cursor, wiringStatus: .wired)
    #expect(followUp?.host == .cursor)
    #expect(followUp?.kind == .goodToKnow)
    #expect(followUp?.text == AgentFollowUps.cursorGoodToKnow)
    #expect(followUp?.offersMarkAsDone == false)
  }

  @Test func cursorGetsNoLineWhenNotWired() {
    #expect(AgentFollowUps.current(host: .cursor, wiringStatus: .notWired) == nil)
  }

  @Test func antigravityGetsAPermanentGoodToKnowLineWhenWired() {
    let followUp = AgentFollowUps.current(host: .antigravity, wiringStatus: .wired)
    #expect(followUp?.host == .antigravity)
    #expect(followUp?.kind == .goodToKnow)
    #expect(followUp?.text == AgentFollowUps.antigravityGoodToKnow)
    #expect(followUp?.offersMarkAsDone == false)
  }

  @Test func codexNextStepSaysHooksOnceAnotherEntryIsThere() {
    #expect(AgentFollowUps.codexNextStep.contains("trust Countersign's hook."))
    #expect(AgentFollowUps.codexNextStep(hasOtherEntries: false) == AgentFollowUps.codexNextStep)
    #expect(
      AgentFollowUps.codexNextStep(hasOtherEntries: true).contains("trust Countersign's hooks."))
    let followUp = AgentFollowUps.current(
      host: .codex, wiringStatus: .wired, codexTrust: .unknown, codexHasOtherEntries: true)
    #expect(followUp?.text == AgentFollowUps.codexNextStepWithOtherEntries)
    let stop = Array(
      #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/opt/homebrew/bin/countersign hook --host codex --event waiting"}]}]}}"#
        .utf8)
    #expect(AgentFollowUps.codexHasOtherEntries(in: .bytes(stop)))
    #expect(!AgentFollowUps.codexHasOtherEntries(in: .bytes(Array("{}".utf8))))
    #expect(!AgentFollowUps.codexHasOtherEntries(in: .missing))
    let context = Array(
      #"{"hooks": {"PermissionRequest": [{"hooks": [{"type": "command", "command": "/opt/homebrew/bin/countersign hook --host codex"}]}], "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/opt/homebrew/bin/countersign hook --host codex", "timeout": 30}]}], "PostToolUse": [{"hooks": [{"type": "command", "command": "/opt/homebrew/bin/countersign hook --host codex", "timeout": 30}]}]}}"#
        .utf8)
    #expect(AgentFollowUps.codexHasOtherEntries(in: .bytes(context)))
    let permissionOnly = Array(
      #"{"hooks": {"PermissionRequest": [{"hooks": [{"type": "command", "command": "/opt/homebrew/bin/countersign hook --host codex"}]}]}}"#
        .utf8)
    #expect(!AgentFollowUps.codexHasOtherEntries(in: .bytes(permissionOnly)))
    let followUp2 = AgentFollowUps.current(
      host: .codex, wiringStatus: .wired, codexTrust: .unknown,
      codexHasOtherEntries: AgentFollowUps.codexHasOtherEntries(in: .bytes(context)))
    #expect(followUp2?.text == AgentFollowUps.codexNextStepWithOtherEntries)
  }

  @Test func antigravityGetsNoLineWhenItNeedsAnUpdate() {
    #expect(
      AgentFollowUps.current(
        host: .antigravity, wiringStatus: .needsUpdate(HostWiringUpdate(otherExecutablePaths: [])))
        == nil)
  }
}
