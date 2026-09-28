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
