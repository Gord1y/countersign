import Testing

@testable import ApprovalCore

@Suite struct DurationTextTests {
  @Test func parsesSeconds() {
    #expect(DurationText.parse("90s") == 90)
  }

  @Test func parsesMinutes() {
    #expect(DurationText.parse("15m") == 900)
  }

  @Test func parsesHours() {
    #expect(DurationText.parse("1h") == 3600)
  }

  @Test func parsesABareNumberAsMinutes() {
    #expect(DurationText.parse("5") == 300)
  }

  @Test func parsesAFractionalBareNumberAsMinutes() {
    #expect(DurationText.parse("1.5") == 90)
  }

  @Test func isCaseInsensitive() {
    #expect(DurationText.parse("15M") == 900)
  }

  @Test func trimsWhitespace() {
    #expect(DurationText.parse("  15m  ") == 900)
  }

  @Test func rejectsEmptyText() {
    #expect(DurationText.parse("") == nil)
  }

  @Test func rejectsZero() {
    #expect(DurationText.parse("0m") == nil)
    #expect(DurationText.parse("0") == nil)
  }

  @Test func rejectsNegativeValues() {
    #expect(DurationText.parse("-5m") == nil)
    #expect(DurationText.parse("-5") == nil)
  }

  @Test func rejectsGarbage() {
    #expect(DurationText.parse("soon") == nil)
    #expect(DurationText.parse("m") == nil)
    #expect(DurationText.parse("5x") == nil)
  }

  @Test func parsesMillisecondsBeforeMinutesAndSeconds() {
    #expect(DurationText.parse("500ms", bareUnit: 1) == 0.5)
    #expect(DurationText.parse("250MS", bareUnit: 1) == 0.25)
  }

  @Test func parsesFractionalSeconds() {
    #expect(DurationText.parse("0.5s", bareUnit: 1) == 0.5)
  }

  @Test func parsesEveryUnitWithTheBareUnitVariant() {
    #expect(DurationText.parse("90s", bareUnit: 60) == 90)
    #expect(DurationText.parse("2m", bareUnit: 1) == 120)
    #expect(DurationText.parse("1h", bareUnit: 1) == 3600)
  }

  @Test func multipliesABareNumberByTheBareUnit() {
    #expect(DurationText.parse("2", bareUnit: 1) == 2)
    #expect(DurationText.parse("2", bareUnit: 60) == 120)
    #expect(DurationText.parse("0.5", bareUnit: 1) == 0.5)
  }

  @Test func theBareUnitVariantAllowsZeroButTheDefaultDoesNot() {
    #expect(DurationText.parse("0", bareUnit: 1) == 0)
    #expect(DurationText.parse("0s", bareUnit: 60) == 0)
    #expect(DurationText.parse("0") == nil)
  }

  @Test func theBareUnitVariantRejectsJunk() {
    #expect(DurationText.parse("soon", bareUnit: 1) == nil)
    #expect(DurationText.parse("ms", bareUnit: 1) == nil)
    #expect(DurationText.parse("5x", bareUnit: 1) == nil)
    #expect(DurationText.parse("-1s", bareUnit: 1) == nil)
    #expect(DurationText.parse("", bareUnit: 1) == nil)
  }

  @Test func compactPicksTheLargestExactUnit() {
    #expect(DurationText.compact(0.5) == "500ms")
    #expect(DurationText.compact(1.5) == "1.5s")
    #expect(DurationText.compact(5) == "5s")
    #expect(DurationText.compact(90) == "90s")
    #expect(DurationText.compact(120) == "2m")
    #expect(DurationText.compact(3600) == "1h")
    #expect(DurationText.compact(5400) == "90m")
  }

  @Test func compactWritesZeroInSeconds() {
    #expect(DurationText.compact(0) == "0s")
  }

  @Test func aDurationTooLargeForAWholeNumberStillFormats() throws {
    let seconds = try #require(DurationText.parse("1e19s"))
    #expect(DurationText.compact(seconds) == "1e+19s")
    #expect(DurationText.describe(seconds) == "1e+19s")
  }

  @Test func describesOneMinute() {
    #expect(DurationText.describe(60) == "1 minute")
  }

  @Test func describesFiveMinutes() {
    #expect(DurationText.describe(300) == "5 minutes")
  }

  @Test func describesThirtyMinutes() {
    #expect(DurationText.describe(1800) == "30 minutes")
  }

  @Test func describesOneHour() {
    #expect(DurationText.describe(3600) == "1 hour")
  }

  @Test func describesTwoHours() {
    #expect(DurationText.describe(7200) == "2 hours")
  }

  @Test func describesRoundingToTheNearestMinute() {
    #expect(DurationText.describe(90) == "2 minutes")
  }

  @Test func describesSecondsBelowAMinute() {
    #expect(DurationText.describe(1) == "1 second")
    #expect(DurationText.describe(30) == "30 seconds")
  }
}
