import Testing

@testable import ApprovalCore

@Suite struct PreferenceRulesTests {
  @Test func boundsMatchTheWindowsControls() {
    #expect(PreferenceRules.armDelayRange == 0...3)
    #expect(PreferenceRules.armDelayStepsPerSecond == 10)
    #expect(PreferenceRules.idleSecondsRange == 1...30)
    #expect(PreferenceRules.graceSecondsRange == 0...30)
    #expect(PreferenceRules.snoozePresetCount == 1...6)
    #expect(Settings.snoozePresetRange == 10...86400)
  }

  @Test func clampsAndRoundsTheTypedArmDelayToMilliseconds() {
    #expect(PreferenceRules.armDelay(-1) == 0)
    #expect(PreferenceRules.armDelay(5) == 3)
    #expect(PreferenceRules.armDelay(0.1 * 3) == 0.3)
    #expect(PreferenceRules.armDelay(1.26) == 1.26)
    #expect(PreferenceRules.armDelay(0.8) == 0.8)
    #expect(PreferenceRules.armDelay(0.2504) == 0.25)
    #expect(String(PreferenceRules.armDelay(0.1 + 0.2)) == "0.3")
  }

  @Test func clampsAndRoundsTheSliderArmDelayToTenths() {
    #expect(PreferenceRules.sliderArmDelay(-1) == 0)
    #expect(PreferenceRules.sliderArmDelay(5) == 3)
    #expect(PreferenceRules.sliderArmDelay(0.1 * 3) == 0.3)
    #expect(PreferenceRules.sliderArmDelay(1.26) == 1.3)
    #expect(String(PreferenceRules.sliderArmDelay(0.1 + 0.2)) == "0.3")
  }

  @Test func clampsAndRoundsTheChainedArmDelayLikeTheArmDelay() {
    #expect(PreferenceRules.chainedArmDelay(-1) == 0)
    #expect(PreferenceRules.chainedArmDelay(5) == 3)
    #expect(PreferenceRules.chainedArmDelay(0) == 0)
    #expect(PreferenceRules.chainedArmDelay(0.14) == 0.14)
    #expect(String(PreferenceRules.chainedArmDelay(0.1 + 0.2)) == "0.3")
  }

  @Test func clampsIdleAndGrace() {
    #expect(PreferenceRules.idleSeconds(0) == 1)
    #expect(PreferenceRules.idleSeconds(45) == 30)
    #expect(PreferenceRules.idleSeconds(2.5) == 2.5)
    #expect(PreferenceRules.graceSeconds(-1) == 0)
    #expect(PreferenceRules.graceSeconds(31) == 30)
    #expect(PreferenceRules.graceSeconds(3) == 3)
  }

  @Test func parsesSnoozePresets() {
    #expect(PreferenceRules.snoozePresets(from: "1, 5, 15, 30") == .success([60, 300, 900, 1800]))
    #expect(PreferenceRules.snoozePresets(from: "  10 ") == .success([600]))
    #expect(PreferenceRules.snoozePresets(from: "1,5") == .success([60, 300]))
    #expect(PreferenceRules.snoozePresets(from: "1 5,, 60") == .success([60, 300, 3600]))
    #expect(
      PreferenceRules.snoozePresets(from: "1, 2, 3, 4, 5, 1440")
        == .success([60, 120, 180, 240, 300, 86400]))
  }

  @Test func parsesSnoozePresetsWithUnits() {
    #expect(PreferenceRules.snoozePresets(from: "30s, 5, 1h") == .success([30, 300, 3600]))
    #expect(PreferenceRules.snoozePresets(from: "15m 90s") == .success([900, 90]))
    #expect(PreferenceRules.snoozePresets(from: "1.5") == .success([90]))
  }

  @Test func rejectsSnoozePresetsOutsideTheSchema() {
    #expect(PreferenceRules.snoozePresets(from: "") == .failure(.empty))
    #expect(PreferenceRules.snoozePresets(from: " , ") == .failure(.empty))
    #expect(PreferenceRules.snoozePresets(from: "5, x") == .failure(.notADuration("x")))
    #expect(PreferenceRules.snoozePresets(from: "0") == .failure(.outOfRange(0)))
    #expect(PreferenceRules.snoozePresets(from: "5s") == .failure(.outOfRange(5)))
    #expect(PreferenceRules.snoozePresets(from: "5, 1441") == .failure(.outOfRange(86460)))
    #expect(PreferenceRules.snoozePresets(from: "1, 2, 3, 4, 5, 6, 7") == .failure(.tooMany(7)))
  }

  @Test func showsWholeMinutesAsBareNumbersAndTheRestWithUnits() {
    #expect(PreferenceRules.snoozeText([60, 300, 900]) == "1, 5, 15")
    #expect(PreferenceRules.snoozeText([30, 300, 3600]) == "30s, 5, 60")
    #expect(PreferenceRules.snoozeText([90]) == "90s")
  }

  @Test func describesSnoozeErrorsInOneLine() {
    #expect(
      SnoozeTextError.empty.description
        == "Enter 1 to 6 presets, like 30s, 5, 15m, 1h (a bare number is minutes)")
    #expect(SnoozeTextError.notADuration("x").description == "\"x\" isn't a duration")
    #expect(SnoozeTextError.outOfRange(0).description == "0s is outside 10s to 24h")
    #expect(SnoozeTextError.outOfRange(1e19).description == "1e+19s is outside 10s to 24h")
    #expect(SnoozeTextError.tooMany(7).description == "7 presets, at most 6 fit the menu")
  }

  @Test func writesSnoozePresetsAsText() {
    #expect(PreferenceRules.snoozeText([60, 300, 900, 1800]) == "1, 5, 15, 30")
    #expect(PreferenceRules.snoozeText([600]) == "10")
  }

  @Test func acceptsATrimmedNewBundleID() {
    #expect(
      PreferenceRules.handoffApp("  com.openai.codex\n", joining: ["com.x"])
        == .success("com.openai.codex"))
  }

  @Test func rejectsAnEmptySpacedOrRepeatedBundleID() {
    #expect(PreferenceRules.handoffApp("  ", joining: []) == .failure(.empty))
    #expect(PreferenceRules.handoffApp("com.x y", joining: []) == .failure(.containsWhitespace))
    #expect(
      PreferenceRules.handoffApp("com.x", joining: ["com.x"]) == .failure(.duplicate("com.x")))
    #expect(HandoffAppError.empty.description == "Enter a bundle ID, like com.openai.codex")
    #expect(HandoffAppError.containsWhitespace.description == "A bundle ID has no spaces")
    #expect(HandoffAppError.duplicate("com.x").description == "com.x is already in the list")
  }

  @Test func readsDurationFieldText() {
    let arm = PreferenceName.armDelay.durationField
    let idle = PreferenceName.idleSeconds.durationField
    let grace = PreferenceName.graceSeconds.durationField
    let notice = PreferenceName.waitingNoticeDelay.durationField
    #expect(arm.map { PreferenceRules.duration(from: "250ms", spec: $0) } == .success(0.25))
    #expect(idle.map { PreferenceRules.duration(from: "2.5", spec: $0) } == .success(2.5))
    #expect(notice.map { PreferenceRules.duration(from: "30", spec: $0) } == .success(30))
    #expect(notice.map { PreferenceRules.duration(from: "90s", spec: $0) } == .success(90))
    #expect(grace.map { PreferenceRules.duration(from: "0", spec: $0) } == .success(0))
    #expect(
      idle.map { PreferenceRules.duration(from: "", spec: $0) } == .failure(.empty(bareUnit: 1)))
    #expect(
      idle.map { PreferenceRules.duration(from: "soon", spec: $0) }
        == .failure(.notADuration("soon")))
    #expect(
      idle.map { PreferenceRules.duration(from: "45s", spec: $0) }
        == .failure(.outOfRange(45, 1...30))
    )
    #expect(idle.map { PreferenceRules.duration(from: "1.23456s", spec: $0) } == .success(1.235))
  }

  @Test func describesDurationFieldErrors() {
    #expect(
      DurationFieldError.empty(bareUnit: 1).description
        == "Enter a duration, like 500ms, 5s or 2m (a bare number is seconds)")
    #expect(
      DurationFieldError.empty(bareUnit: 60).description
        == "Enter a duration, like 90s, 5 or 1h (a bare number is minutes)")
    #expect(DurationFieldError.notADuration("soon").description == "\"soon\" isn't a duration")
    #expect(
      DurationFieldError.outOfRange(45, 1...30).description == "45s is outside 1s to 30s")
  }

  @Test func namesTheDurationFields() {
    #expect(
      PreferenceName.idleSeconds.durationField
        == DurationFieldSpec(bareUnit: 1, range: Settings.idleSecondsRange))
    #expect(
      PreferenceName.graceSeconds.durationField
        == DurationFieldSpec(bareUnit: 1, range: Settings.graceSecondsRange))
    #expect(
      PreferenceName.armDelay.durationField
        == DurationFieldSpec(bareUnit: 1, range: Settings.armDelayRange))
    #expect(
      PreferenceName.chainedArmDelay.durationField
        == DurationFieldSpec(bareUnit: 1, range: Settings.armDelayRange))
    #expect(
      PreferenceName.waitingNoticeDelay.durationField
        == DurationFieldSpec(bareUnit: 1, range: Settings.waitingNoticeDelayRange))
    #expect(
      PreferenceName.waitingNoticeDuration.durationField
        == DurationFieldSpec(bareUnit: 1, range: 3...3600))
    #expect(
      PreferenceName.approvalCardDelay.durationField
        == DurationFieldSpec(bareUnit: 1, range: 1...600))
    #expect(PreferenceName.snoozeMinutes.durationField == nil)
    #expect(PreferenceName.questionNotes.durationField == nil)
  }

  @Test func writesSecondsWithoutATrailingZero() {
    #expect(PreferenceRules.secondsText(0.8) == "0.8 s")
    #expect(PreferenceRules.secondsText(5) == "5 s")
    #expect(PreferenceRules.secondsText(0) == "0 s")
    #expect(PreferenceRules.numberText(2.5) == "2.5")
    #expect(PreferenceRules.numberText(.infinity) == "inf")
  }
}
