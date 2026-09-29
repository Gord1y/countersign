import Foundation
import Testing

@testable import ApprovalCore

@Suite struct SettingsHeaderControlsTests {
  private let utc = TimeZone(identifier: "UTC") ?? .current
  private let deadline = Date(timeIntervalSince1970: 1_700_000_000 + 3600)

  @Test func showsNoTintOrCaptionWhileActive() {
    let controls = SettingsHeaderControls(status: .active)
    #expect(controls.pauseTint == .secondary)
    #expect(controls.pauseHelp == "Pause Countersign")
    #expect(controls.snoozeTint == .secondary)
    #expect(controls.snoozeIsEnabled)
    #expect(controls.caption(timeZone: utc) == nil)
    #expect(controls.quietHeading(timeZone: utc) == nil)
  }

  @Test func tintsPauseYellowAndDisablesSnoozeWhilePaused() {
    let controls = SettingsHeaderControls(status: .paused)
    #expect(controls.pauseTint == .yellow)
    #expect(controls.pauseHelp == "Resume Countersign")
    #expect(!controls.snoozeIsEnabled)
    #expect(controls.snoozeTint == .secondary)
    #expect(controls.caption(timeZone: utc)?.text == "Paused")
    #expect(controls.caption(timeZone: utc)?.tint == .yellow)
  }

  @Test func namesAPauseThatLastsUntilCountersignOpens() {
    let controls = SettingsHeaderControls(status: .pausedUntilAppOpens)
    #expect(controls.pauseTint == .yellow)
    #expect(!controls.snoozeIsEnabled)
    #expect(controls.caption(timeZone: utc)?.text == "Paused until Countersign opens")
  }

  @Test func tintsSnoozeBlueDuringQuietTime() {
    let controls = SettingsHeaderControls(status: .quiet(until: deadline))
    #expect(controls.pauseTint == .secondary)
    #expect(controls.pauseHelp == "Pause Countersign")
    #expect(controls.snoozeTint == .blue)
    #expect(controls.snoozeIsEnabled)
    #expect(controls.quietUntil == deadline)
    #expect(controls.caption(timeZone: utc)?.text == "Until 23:13")
    #expect(controls.caption(timeZone: utc)?.tint == .blue)
    #expect(controls.quietHeading(timeZone: utc) == "Quiet until 23:13")
  }
}
