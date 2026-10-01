import Testing

@testable import ApprovalCore

@Suite struct SnoozeTitleTests {
  @Test func firstOptionReadsQuietFor() {
    #expect(SnoozeTitle.describe(seconds: 60, isFirst: true) == "Quiet for 1 minute")
    #expect(SnoozeTitle.describe(seconds: 900, isFirst: true) == "Quiet for 15 minutes")
  }

  @Test func laterOptionsAreJustTheDuration() {
    #expect(SnoozeTitle.describe(seconds: 300, isFirst: false) == "5 minutes")
    #expect(SnoozeTitle.describe(seconds: 60, isFirst: false) == "1 minute")
  }

  @Test func wholeHoursReadAsHours() {
    #expect(SnoozeTitle.describe(seconds: 3600, isFirst: false) == "1 hour")
    #expect(SnoozeTitle.describe(seconds: 7200, isFirst: true) == "Quiet for 2 hours")
    #expect(SnoozeTitle.describe(seconds: 5400, isFirst: false) == "90 minutes")
  }

  @Test func subMinuteAndPartMinuteOptionsReadInSeconds() {
    #expect(SnoozeTitle.describe(seconds: 30, isFirst: true) == "Quiet for 30 seconds")
    #expect(SnoozeTitle.describe(seconds: 90, isFirst: false) == "90 seconds")
  }
}
