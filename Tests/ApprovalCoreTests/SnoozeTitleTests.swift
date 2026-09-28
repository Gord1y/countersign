import Testing

@testable import ApprovalCore

@Suite struct SnoozeTitleTests {
  @Test func firstOptionReadsQuietFor() {
    #expect(SnoozeTitle.describe(minutes: 1, isFirst: true) == "Quiet for 1 minute")
    #expect(SnoozeTitle.describe(minutes: 15, isFirst: true) == "Quiet for 15 minutes")
  }

  @Test func laterOptionsAreJustTheDuration() {
    #expect(SnoozeTitle.describe(minutes: 5, isFirst: false) == "5 minutes")
    #expect(SnoozeTitle.describe(minutes: 1, isFirst: false) == "1 minute")
  }

  @Test func wholeHoursReadAsHours() {
    #expect(SnoozeTitle.describe(minutes: 60, isFirst: false) == "1 hour")
    #expect(SnoozeTitle.describe(minutes: 120, isFirst: true) == "Quiet for 2 hours")
    #expect(SnoozeTitle.describe(minutes: 90, isFirst: false) == "90 minutes")
  }
}
