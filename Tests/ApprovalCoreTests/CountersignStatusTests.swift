import Foundation
import Testing

@testable import ApprovalCore

@Suite struct CountersignStatusTests {
  private static let quietUntil = Date(timeIntervalSince1970: 14 * 3600 + 5 * 60)

  @Test func isActiveWithoutPauseOrQuietTime() {
    let status = CountersignStatus.current(pause: .active, quietUntil: nil)
    #expect(status == .active)
    #expect(status.icon == .active)
    #expect(status.title(timeZone: .gmt) == "Countersign is on")
    #expect(status.detail == "Requests from wired hosts show a panel.")
    #expect(status.action == .pause)
    #expect(status.action.title == "Pause")
  }

  @Test func isPausedWhileThePauseSwitchIsOn() {
    let status = CountersignStatus.current(pause: .paused, quietUntil: nil)
    #expect(status == .paused)
    #expect(status.icon == .paused)
    #expect(status.title(timeZone: .gmt) == "Paused")
    #expect(status.detail == "Every request goes to its chat until you resume.")
    #expect(status.action == .resume)
    #expect(status.action.title == "Resume")
  }

  @Test func saysAPauseSetAtQuitLastsUntilCountersignOpens() {
    let status = CountersignStatus.current(pause: .pausedUntilAppOpens, quietUntil: nil)
    #expect(status == .pausedUntilAppOpens)
    #expect(status.icon == .paused)
    #expect(status.title(timeZone: .gmt) == "Paused until Countersign opens")
    #expect(
      status.detail == "Every request goes to its chat until you open Countersign or resume.")
    #expect(status.action == .resume)
  }

  @Test func isQuietUntilTheDeadline() throws {
    let status = CountersignStatus.current(pause: .active, quietUntil: Self.quietUntil)
    #expect(status == .quiet(until: Self.quietUntil))
    #expect(status.icon == .quiet)
    #expect(status.title(timeZone: .gmt) == "Quiet until 14:05")
    let plusThree = try #require(TimeZone(secondsFromGMT: 3 * 3600))
    #expect(status.title(timeZone: plusThree) == "Quiet until 17:05")
    #expect(
      status.detail == "Panels wait until then; each request can still be answered in its chat.")
    #expect(status.action == .endQuietTime)
    #expect(status.action.title == "End now")
  }

  @Test func pauseWinsOverQuietTime() {
    #expect(CountersignStatus.current(pause: .paused, quietUntil: Self.quietUntil) == .paused)
    #expect(
      CountersignStatus.current(pause: .pausedUntilAppOpens, quietUntil: Self.quietUntil)
        == .pausedUntilAppOpens)
  }

  @Test func usesTheLocalTimeZoneByDefault() {
    let status = CountersignStatus.quiet(until: Self.quietUntil)
    #expect(status.title() == "Quiet until \(TimeOfDayText.describe(Self.quietUntil))")
  }
}
