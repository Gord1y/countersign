import Foundation
import Testing

@testable import ApprovalCore

@Suite struct TimeOfDayTextTests {
  private func date(hour: Int, minute: Int, second: Int = 0) -> Date {
    Date(timeIntervalSince1970: TimeInterval(hour * 3600 + minute * 60 + second))
  }

  @Test func formatsHoursAndMinutesInTwentyFourHourTime() {
    #expect(TimeOfDayText.describe(date(hour: 14, minute: 5), timeZone: .gmt) == "14:05")
    #expect(TimeOfDayText.describe(date(hour: 23, minute: 59), timeZone: .gmt) == "23:59")
    #expect(TimeOfDayText.describe(date(hour: 0, minute: 0), timeZone: .gmt) == "00:00")
  }

  @Test func padsSingleDigitHours() {
    #expect(TimeOfDayText.describe(date(hour: 9, minute: 5), timeZone: .gmt) == "09:05")
  }

  @Test func dropsSecondsWithoutRounding() {
    #expect(
      TimeOfDayText.describe(date(hour: 14, minute: 5, second: 59), timeZone: .gmt) == "14:05")
  }

  @Test func usesTheGivenTimeZone() throws {
    let plusThree = try #require(TimeZone(secondsFromGMT: 3 * 3600))
    let minusFive = try #require(TimeZone(secondsFromGMT: -5 * 3600))

    #expect(TimeOfDayText.describe(date(hour: 14, minute: 5), timeZone: plusThree) == "17:05")
    #expect(TimeOfDayText.describe(date(hour: 3, minute: 30), timeZone: minusFive) == "22:30")
  }

  @Test func defaultsToTheCurrentTimeZone() {
    let moment = date(hour: 14, minute: 5)
    #expect(
      TimeOfDayText.describe(moment) == TimeOfDayText.describe(moment, timeZone: .current))
  }
}
