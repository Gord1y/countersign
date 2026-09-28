import Testing

@testable import ApprovalCore

@Suite struct PermissionModeDisplayTests {
  @Test func defaultModeShowsNoChip() {
    #expect(PermissionModeDisplay.forMode("default", host: .claude) == nil)
  }

  @Test func emptyModeShowsNoChip() {
    #expect(PermissionModeDisplay.forMode("", host: .claude) == nil)
    #expect(PermissionModeDisplay.forMode("   ", host: .claude) == nil)
  }

  @Test func absentModeShowsNoChip() {
    #expect(PermissionModeDisplay.forMode(nil, host: .claude) == nil)
  }

  @Test func planMode() {
    let display = PermissionModeDisplay.forMode("plan", host: .claude)
    #expect(display?.label == "Plan mode")
    #expect(
      display?.tooltip
        == "Claude is planning and won't change anything until you approve a plan.")
  }

  @Test func acceptEditsMode() {
    let display = PermissionModeDisplay.forMode("acceptEdits", host: .claude)
    #expect(display?.label == "Accepting edits")
    #expect(
      display?.tooltip
        == "File edits in this session are approved automatically. Other tools still ask.")
  }

  @Test func bypassPermissionsMode() {
    let display = PermissionModeDisplay.forMode("bypassPermissions", host: .claude)
    #expect(display?.label == "Bypassing permissions")
    #expect(display?.tooltip == "Tools run without asking in this session.")
  }

  @Test func dontAskMode() {
    let display = PermissionModeDisplay.forMode("dontAsk", host: .codex)
    #expect(display?.label == "Don't ask")
    #expect(
      display?.tooltip == "Tools that aren't already allowed are denied without asking.")
  }

  @Test func autoMode() {
    let display = PermissionModeDisplay.forMode("auto", host: .claude)
    #expect(display?.label == "Auto mode")
    #expect(
      display?.tooltip
        == "Routine actions are approved automatically. Risky ones still ask.")
  }

  @Test func unknownModeShowsTheRawValueAndHostTooltip() {
    let display = PermissionModeDisplay.forMode("yolo", host: .claude)
    #expect(display?.label == "yolo")
    #expect(display?.tooltip == "Permission mode reported by Claude Code.")
  }

  @Test func unknownModeNamesTheReportingHost() {
    let display = PermissionModeDisplay.forMode("yolo", host: .codex)
    #expect(display?.tooltip == "Permission mode reported by Codex.")
  }

  @Test func trimsWhitespaceBeforeMatching() {
    let display = PermissionModeDisplay.forMode("  plan  ", host: .claude)
    #expect(display?.label == "Plan mode")
  }
}
