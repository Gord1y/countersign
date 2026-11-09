import Foundation
import Testing

@testable import ApprovalCore

@Suite struct KeepAwakeCommandTextTests {
  private let utc = TimeZone(identifier: "UTC") ?? .gmt
  private let evening = Date(timeIntervalSince1970: 1_800_000_000)

  private var evening22h34: Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 1
    components.hour = 22
    components.minute = 34
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: components) ?? evening
  }

  @Test func startedNamesTheEndTime() {
    #expect(
      KeepAwakeCommandText.started(.at(evening22h34), timeZone: utc)
        == "keeping this Mac awake until 22:34; the display still turns off and locks")
  }

  @Test func startedForeverSaysUntilYouTurnItOff() {
    #expect(
      KeepAwakeCommandText.started(.untilTurnedOff, timeZone: utc)
        == "keeping this Mac awake until you turn it off; the display still turns off and locks")
  }

  private func line(
    optedIn: Bool = true, appRunning: Bool = true, state: KeepAwakeState
  ) -> String {
    KeepAwakeCommandText.statusLine(
      optedIn: optedIn, appRunning: appRunning, state: state, timeZone: utc)
  }

  @Test func statusLineCoversEveryRow() {
    let end = evening22h34
    #expect(line(optedIn: false, state: .holding(.untilTurnedOff)) == "off")
    #expect(
      line(appRunning: false, state: .holding(.untilTurnedOff))
        == "not running (the menu-bar app is closed)")
    #expect(line(state: .notRunning) == "not running")
    #expect(line(state: .holding(.at(end))) == "holding until 22:34")
    #expect(line(state: .holding(.untilTurnedOff)) == "holding until turned off")
    #expect(
      line(state: .releasedAtCutoff(.at(end), cutoff: 15))
        == "released at 15% battery; holds again if plugged in, until 22:34")
    #expect(
      line(state: .releasedAtCutoff(.untilTurnedOff, cutoff: 15))
        == "released at 15% battery; holds again if plugged in")
  }
}
