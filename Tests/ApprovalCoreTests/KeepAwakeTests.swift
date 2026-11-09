import Foundation
import Testing

@testable import ApprovalCore

@Suite struct KeepAwakeTests {
  private let utc = TimeZone(identifier: "UTC") ?? .current
  private let evening = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func durationRawValuesSecondsAndTitles() {
    #expect(
      KeepAwakeDuration.allCases == [
        .oneHour, .fourHours, .eightHours, .twelveHours, .untilTurnedOff,
      ])
    #expect(KeepAwakeDuration.allCases.map(\.rawValue) == ["1h", "4h", "8h", "12h", "forever"])
    #expect(KeepAwakeDuration.allCases.map(\.seconds) == [3600, 14400, 28800, 43200, nil])
    #expect(
      KeepAwakeDuration.allCases.map(\.settingsTitle) == [
        "1 hour", "4 hours", "8 hours", "12 hours", "Until I turn it off",
      ])
    #expect(
      KeepAwakeDuration.allCases.map(\.menuTitle) == [
        "For 1 Hour", "For 4 Hours", "For 8 Hours", "For 12 Hours", "Until I Turn It Off",
      ])
  }

  @Test func durationEndIsTimedOrForever() {
    #expect(
      KeepAwakeDuration.fourHours.end(from: evening) == .at(evening.addingTimeInterval(14400)))
    #expect(KeepAwakeDuration.untilTurnedOff.end(from: evening) == .untilTurnedOff)
  }

  @Test func powerFromTheInternalBatteryDescription() {
    #expect(KeepAwakePower(internalBatteryState: nil, capacity: 50, maxCapacity: 100) == .noBattery)
    #expect(
      KeepAwakePower(internalBatteryState: "AC Power", capacity: 50, maxCapacity: 100)
        == .pluggedIn)
    #expect(
      KeepAwakePower(internalBatteryState: "Battery Power", capacity: 73, maxCapacity: 100)
        == .battery(percent: 73))
    #expect(
      KeepAwakePower(internalBatteryState: "Battery Power", capacity: 1, maxCapacity: 3)
        == .battery(percent: 33))
    #expect(
      KeepAwakePower(internalBatteryState: "Battery Power", capacity: 50, maxCapacity: 0)
        == .noBattery)
    #expect(
      KeepAwakePower(internalBatteryState: "Battery Power", capacity: nil, maxCapacity: 100)
        == .noBattery)
    #expect(
      KeepAwakePower(internalBatteryState: "Battery Power", capacity: 50, maxCapacity: nil)
        == .noBattery)
    #expect(
      KeepAwakePower(internalBatteryState: "Mystery", capacity: 50, maxCapacity: 100)
        == .noBattery)
  }

  @Test func anOverFullReadingIsClampedToOneHundred() {
    #expect(
      KeepAwakePower(internalBatteryState: "Battery Power", capacity: Int.max, maxCapacity: 1)
        == .battery(percent: 100))
  }

  @Test func policyIsNotRunningWithoutOptInOrSession() {
    let end = KeepAwakeEnd.at(evening)
    #expect(
      KeepAwakePolicy.state(optedIn: false, session: end, power: .pluggedIn, cutoff: 15)
        == .notRunning)
    #expect(
      KeepAwakePolicy.state(optedIn: true, session: nil, power: .pluggedIn, cutoff: 15)
        == .notRunning)
  }

  @Test func policyAppliesTheCutoffOnBatteryOnly() {
    let end = KeepAwakeEnd.at(evening)
    #expect(
      KeepAwakePolicy.state(optedIn: true, session: end, power: .battery(percent: 16), cutoff: 15)
        == .holding(end))
    #expect(
      KeepAwakePolicy.state(optedIn: true, session: end, power: .battery(percent: 15), cutoff: 15)
        == .releasedAtCutoff(end, cutoff: 15))
    #expect(
      KeepAwakePolicy.state(optedIn: true, session: end, power: .battery(percent: 3), cutoff: 15)
        == .releasedAtCutoff(end, cutoff: 15))
    #expect(
      KeepAwakePolicy.state(optedIn: true, session: end, power: .pluggedIn, cutoff: 95)
        == .holding(end))
    #expect(
      KeepAwakePolicy.state(optedIn: true, session: end, power: .noBattery, cutoff: 95)
        == .holding(end))
  }

  @Test func policyCarriesForeverThroughHoldingAndReleased() {
    #expect(
      KeepAwakePolicy.state(
        optedIn: true, session: .untilTurnedOff, power: .pluggedIn, cutoff: 15)
        == .holding(.untilTurnedOff))
    #expect(
      KeepAwakePolicy.state(
        optedIn: true, session: .untilTurnedOff, power: .battery(percent: 10), cutoff: 15)
        == .releasedAtCutoff(.untilTurnedOff, cutoff: 15))
  }

  @Test func statusTextForEveryState() {
    let end = KeepAwakeEnd.at(Date(timeIntervalSince1970: 1_700_000_000 + 3 * 3600))
    let clock = TimeOfDayText.describe(Date(timeIntervalSince1970: 1_700_010_800), timeZone: utc)
    #expect(clock == "01:13")
    let holdingAt = KeepAwakeState.holding(end)
    let holdingForever = KeepAwakeState.holding(.untilTurnedOff)
    let releasedAt = KeepAwakeState.releasedAtCutoff(end, cutoff: 15)
    let releasedForever = KeepAwakeState.releasedAtCutoff(.untilTurnedOff, cutoff: 15)

    #expect(KeepAwakeState.notRunning.statusTitle == "Not running")
    #expect(
      KeepAwakeState.notRunning.statusCaption(timeZone: utc)
        == "Start it here or from the menu bar.")
    #expect(holdingAt.statusTitle == "Keeping this Mac awake")
    #expect(
      holdingAt.statusCaption(timeZone: utc)
        == "Until 01:13. The display still turns off and locks.")
    #expect(holdingForever.statusTitle == "Keeping this Mac awake")
    #expect(
      holdingForever.statusCaption(timeZone: utc)
        == "Until you turn it off. The display still turns off and locks.")
    #expect(releasedAt.statusTitle == "Released at 15% battery")
    #expect(
      releasedAt.statusCaption(timeZone: utc) == "Holds again if you plug in, until 01:13.")
    #expect(releasedForever.statusTitle == "Released at 15% battery")
    #expect(releasedForever.statusCaption(timeZone: utc) == "Holds again if you plug in.")
  }

  @Test func stateFlagsAndEnd() {
    let end = KeepAwakeEnd.at(evening)
    #expect(!KeepAwakeState.notRunning.isRunning)
    #expect(!KeepAwakeState.notRunning.holdsIdleSleep)
    #expect(KeepAwakeState.notRunning.end == nil)
    #expect(KeepAwakeState.holding(end).isRunning)
    #expect(KeepAwakeState.holding(end).holdsIdleSleep)
    #expect(KeepAwakeState.holding(end).end == end)
    #expect(KeepAwakeState.releasedAtCutoff(.untilTurnedOff, cutoff: 15).isRunning)
    #expect(!KeepAwakeState.releasedAtCutoff(.untilTurnedOff, cutoff: 15).holdsIdleSleep)
    #expect(KeepAwakeState.releasedAtCutoff(.untilTurnedOff, cutoff: 15).end == .untilTurnedOff)
  }
}
