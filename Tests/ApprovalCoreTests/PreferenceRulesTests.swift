import Testing

@testable import ApprovalCore

@Suite struct PreferenceRulesTests {
  @Test func boundsMatchTheWindowsControls() {
    #expect(PreferenceRules.armDelayRange == 0...3)
    #expect(PreferenceRules.armDelayStepsPerSecond == 10)
    #expect(PreferenceRules.idleSecondsRange == 1...30)
    #expect(PreferenceRules.graceSecondsRange == 0...30)
    #expect(PreferenceRules.snoozePresetCount == 1...6)
    #expect(PreferenceRules.snoozeMinuteRange == 1...1440)
  }

  @Test func clampsAndRoundsTheArmDelayToTenths() {
    #expect(PreferenceRules.armDelay(-1) == 0)
    #expect(PreferenceRules.armDelay(5) == 3)
    #expect(PreferenceRules.armDelay(0.1 * 3) == 0.3)
    #expect(PreferenceRules.armDelay(1.26) == 1.3)
    #expect(PreferenceRules.armDelay(0.8) == 0.8)
    #expect(String(PreferenceRules.armDelay(0.1 + 0.2)) == "0.3")
  }

  @Test func clampsAndRoundsTheChainedArmDelayLikeTheArmDelay() {
    #expect(PreferenceRules.chainedArmDelay(-1) == 0)
    #expect(PreferenceRules.chainedArmDelay(5) == 3)
    #expect(PreferenceRules.chainedArmDelay(0) == 0)
    #expect(PreferenceRules.chainedArmDelay(0.14) == 0.1)
    #expect(PreferenceRules.chainedArmDelay(0.16) == 0.2)
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
    #expect(PreferenceRules.snoozeMinutes(from: "1, 5, 15, 30") == .success([1, 5, 15, 30]))
    #expect(PreferenceRules.snoozeMinutes(from: "  10 ") == .success([10]))
    #expect(PreferenceRules.snoozeMinutes(from: "1,5") == .success([1, 5]))
    #expect(PreferenceRules.snoozeMinutes(from: "1 5,, 60") == .success([1, 5, 60]))
    #expect(
      PreferenceRules.snoozeMinutes(from: "1, 2, 3, 4, 5, 1440") == .success([1, 2, 3, 4, 5, 1440]))
  }

  @Test func rejectsSnoozePresetsOutsideTheSchema() {
    #expect(PreferenceRules.snoozeMinutes(from: "") == .failure(.empty))
    #expect(PreferenceRules.snoozeMinutes(from: " , ") == .failure(.empty))
    #expect(PreferenceRules.snoozeMinutes(from: "5, x") == .failure(.notAWholeNumber("x")))
    #expect(PreferenceRules.snoozeMinutes(from: "1.5") == .failure(.notAWholeNumber("1.5")))
    #expect(PreferenceRules.snoozeMinutes(from: "0") == .failure(.outOfRange(0)))
    #expect(PreferenceRules.snoozeMinutes(from: "5, 1441") == .failure(.outOfRange(1441)))
    #expect(PreferenceRules.snoozeMinutes(from: "1, 2, 3, 4, 5, 6, 7") == .failure(.tooMany(7)))
  }

  @Test func describesSnoozeErrorsInOneLine() {
    #expect(
      SnoozeTextError.empty.description == "Enter 1 to 6 presets in minutes, like 1, 5, 15, 30")
    #expect(
      SnoozeTextError.notAWholeNumber("x").description == "\"x\" is not a whole number of minutes")
    #expect(SnoozeTextError.outOfRange(0).description == "0 is outside 1 to 1440 minutes")
    #expect(SnoozeTextError.tooMany(7).description == "7 presets, at most 6 fit the menu")
  }

  @Test func writesSnoozePresetsAsText() {
    #expect(PreferenceRules.snoozeText([1, 5, 15, 30]) == "1, 5, 15, 30")
    #expect(PreferenceRules.snoozeText([10]) == "10")
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

  @Test func writesSecondsWithoutATrailingZero() {
    #expect(PreferenceRules.secondsText(0.8) == "0.8 s")
    #expect(PreferenceRules.secondsText(5) == "5 s")
    #expect(PreferenceRules.secondsText(0) == "0 s")
    #expect(PreferenceRules.numberText(2.5) == "2.5")
    #expect(PreferenceRules.numberText(.infinity) == "inf")
  }
}
