import Foundation
import Testing

@testable import ApprovalCore

@Suite struct QuietScheduleTests {
  private static let kyiv = TimeZone(identifier: "Europe/Kyiv") ?? .gmt

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Self.kyiv
    return calendar
  }

  private func local(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    let components = DateComponents(
      timeZone: Self.kyiv, year: 2026, month: month, day: day, hour: hour, minute: minute)
    return calendar.date(from: components) ?? .distantPast
  }

  private func instant(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? .distantPast
  }

  private func window(_ days: [QuietWeekday], _ from: String, _ to: String) throws -> QuietWindow {
    try #require(QuietWindow(days: days, from: from, to: to))
  }

  private func schedule(_ windows: QuietWindow...) -> QuietSchedule {
    QuietSchedule(windows: windows)
  }

  @Test func sameDayWindowIsActiveInsideIt() throws {
    let quiet = try schedule(window([.mon], "09:00", "17:00"))

    let active = quiet.activeWindow(at: local(10, 19, 12, 0), calendar: calendar)

    #expect(active?.start == local(10, 19, 9, 0))
    #expect(active?.end == local(10, 19, 17, 0))
  }

  @Test func sameDayWindowIsInactiveOutsideIt() throws {
    let quiet = try schedule(window([.mon], "09:00", "17:00"))

    #expect(quiet.activeWindow(at: local(10, 19, 8, 59), calendar: calendar) == nil)
    #expect(quiet.activeWindow(at: local(10, 19, 17, 30), calendar: calendar) == nil)
  }

  @Test func overnightWindowStartingFridayIsActiveSaturdayAtThree() throws {
    let quiet = try schedule(window([.fri], "22:00", "09:00"))

    let active = quiet.activeWindow(at: local(10, 24, 3, 0), calendar: calendar)

    #expect(active?.start == local(10, 23, 22, 0))
    #expect(active?.end == local(10, 24, 9, 0))
  }

  @Test func overnightWindowIsActiveOnItsStartDayEvening() throws {
    let quiet = try schedule(window([.fri], "22:00", "09:00"))

    let active = quiet.activeWindow(at: local(10, 23, 23, 30), calendar: calendar)

    #expect(active?.end == local(10, 24, 9, 0))
  }

  @Test func overnightWindowDoesNotStartOnTheDayAfter() throws {
    let quiet = try schedule(window([.fri], "22:00", "09:00"))

    #expect(quiet.activeWindow(at: local(10, 24, 23, 0), calendar: calendar) == nil)
    #expect(quiet.activeWindow(at: local(10, 25, 3, 0), calendar: calendar) == nil)
  }

  @Test func dayNotListedIsInactive() throws {
    let quiet = try schedule(window([.mon, .wed], "09:00", "17:00"))

    #expect(quiet.activeWindow(at: local(10, 20, 12, 0), calendar: calendar) == nil)
  }

  @Test func theWindowEndsAtTheMinuteToIsReached() throws {
    let quiet = try schedule(window([.mon], "09:00", "17:00"))

    #expect(quiet.activeWindow(at: local(10, 19, 16, 59), calendar: calendar) != nil)
    #expect(quiet.activeWindow(at: local(10, 19, 17, 0), calendar: calendar) == nil)
    #expect(quiet.activeWindow(at: local(10, 19, 9, 0), calendar: calendar) != nil)
  }

  @Test func windowFollowsTheWallClockOnAFallBackDay() throws {
    let quiet = try schedule(window([.sat], "22:00", "09:00"))
    let firstThreeThirty = instant("2026-10-25T00:30:00Z")
    let secondThreeThirty = instant("2026-10-25T01:30:00Z")

    let first = quiet.activeWindow(at: firstThreeThirty, calendar: calendar)
    let second = quiet.activeWindow(at: secondThreeThirty, calendar: calendar)

    #expect(first?.start == instant("2026-10-24T19:00:00Z"))
    #expect(first?.end == instant("2026-10-25T07:00:00Z"))
    #expect(second?.end == instant("2026-10-25T07:00:00Z"))
    #expect(
      quiet.activeWindow(at: instant("2026-10-25T06:59:00Z"), calendar: calendar) != nil)
    #expect(
      quiet.activeWindow(at: instant("2026-10-25T07:00:00Z"), calendar: calendar) == nil)
  }

  @Test func windowStartsOnTheWallClockOnAFallBackDay() throws {
    let quiet = try schedule(window([.sun], "10:00", "12:00"))

    let active = quiet.activeWindow(at: instant("2026-10-25T08:30:00Z"), calendar: calendar)

    #expect(active?.start == instant("2026-10-25T08:00:00Z"))
    #expect(active?.end == instant("2026-10-25T10:00:00Z"))
  }

  @Test func overlappingWindowsReportTheLaterEnd() throws {
    let quiet = try schedule(
      try window([.mon], "09:00", "12:00"), window([.mon], "10:00", "15:00"))

    let active = quiet.activeWindow(at: local(10, 19, 11, 0), calendar: calendar)

    #expect(active?.end == local(10, 19, 15, 0))
  }

  @Test func contiguousWindowsReportTheMergedRun() throws {
    let quiet = try schedule(
      try window([.mon], "19:00", "00:00"), window([.tue], "00:00", "09:00"))

    let active = quiet.activeWindow(at: local(10, 19, 20, 0), calendar: calendar)

    #expect(active?.start == local(10, 19, 19, 0))
    #expect(active?.end == local(10, 20, 9, 0))
    #expect(
      quiet.activeWindow(at: local(10, 20, 3, 0), calendar: calendar)?.end == local(10, 20, 9, 0))
  }

  @Test func aChainOfContiguousWindowsIsOneRun() throws {
    let quiet = try schedule(
      try window([.mon], "18:00", "00:00"), window([.tue], "00:00", "12:00"),
      window([.tue], "12:00", "13:00"))

    let active = quiet.activeWindow(at: local(10, 19, 19, 0), calendar: calendar)

    #expect(active?.end == local(10, 20, 13, 0))
  }

  @Test func windowsWithAGapAreSeparateRuns() throws {
    let quiet = try schedule(
      try window([.mon], "19:00", "00:00"), window([.tue], "00:01", "09:00"))

    let active = quiet.activeWindow(at: local(10, 19, 20, 0), calendar: calendar)

    #expect(active?.end == local(10, 20, 0, 0))
  }

  @Test func anEmptyScheduleIsNeverActive() throws {
    #expect(QuietSchedule(windows: []).activeWindow(at: Date(), calendar: calendar) == nil)
  }

  @Test func windowNeedsADayAndDifferentTimes() throws {
    #expect(QuietWindow(days: [], from: "19:00", to: "09:00") == nil)
    #expect(QuietWindow(days: [.mon], from: "19:00", to: "19:00") == nil)
    #expect(QuietWindow(days: [.mon], from: "24:00", to: "09:00") == nil)
    #expect(QuietWindow(days: [.mon], from: "19:60", to: "09:00") == nil)
    #expect(QuietWindow(days: [.mon], from: "7:00", to: "09:00") == nil)
    #expect(QuietWindow(days: [.mon], from: "19:00", to: "") == nil)
  }

  @Test func windowsAreTitledByTheirDayRuns() throws {
    #expect(
      try window([.fri, .mon, .tue, .wed, .thu], "19:00", "09:00").title == "Mon–Fri 19:00–09:00")
    #expect(try window([.sat, .sun], "00:00", "12:00").title == "Sat, Sun 00:00–12:00")
    #expect(
      try window([.mon, .wed, .thu, .fri], "08:05", "18:30").title == "Mon, Wed–Fri 08:05–18:30")
    #expect(try window([.tue], "08:05", "18:30").title == "Tue 08:05–18:30")
  }

  @Test func windowKeepsDaysInWeekOrderWithoutDuplicates() throws {
    #expect(try window([.sun, .mon, .mon], "01:00", "02:00").days == [.mon, .sun])
  }
}

@Suite struct QuietStateTests {
  private static let kyiv = TimeZone(identifier: "Europe/Kyiv") ?? .gmt

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Self.kyiv
    return calendar
  }

  private func local(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    let components = DateComponents(
      timeZone: Self.kyiv, year: 2026, month: month, day: day, hour: hour, minute: minute)
    return calendar.date(from: components) ?? .distantPast
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-quietstate-\(UUID().uuidString)")
  }

  private func state(in directory: URL, windows: [QuietWindow]) -> QuietState {
    QuietState(
      quietTime: QuietTime(file: directory.appendingPathComponent("quiet-until")),
      skippedWindowFile: directory.appendingPathComponent("quiet-hours-skipped-until"),
      schedule: QuietSchedule(windows: windows), calendar: calendar)
  }

  private var weeknights: [QuietWindow] {
    QuietWindow(days: [.mon, .tue, .wed, .thu, .fri], from: "19:00", to: "09:00").map { [$0] }
      ?? []
  }

  @Test func endNowSkipsTheWholeContiguousRun() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let windows = [
      QuietWindow(days: [.mon], from: "19:00", to: "00:00"),
      QuietWindow(days: [.tue], from: "00:00", to: "09:00"),
      QuietWindow(days: [.wed], from: "19:00", to: "23:00"),
    ].compactMap { $0 }
    let quiet = state(in: directory, windows: windows)
    let now = local(10, 19, 20, 0)

    #expect(quiet.activeUntil(now: now) == local(10, 20, 9, 0))
    try quiet.endNow(now: now)

    #expect(quiet.activeUntil(now: now) == nil)
    #expect(quiet.activeUntil(now: local(10, 20, 3, 0)) == nil)
    #expect(quiet.activeUntil(now: local(10, 21, 20, 0)) == local(10, 21, 23, 0))
  }

  @Test func aRunningWindowIsQuietUntilItsEnd() throws {
    let directory = temporaryDirectory()
    let quiet = state(in: directory, windows: weeknights)

    #expect(quiet.activeUntil(now: local(10, 20, 23, 0)) == local(10, 21, 9, 0))
    #expect(quiet.activeUntil(now: local(10, 21, 12, 0)) == nil)
  }

  @Test func withoutWindowsOrSnoozeNothingIsQuiet() throws {
    let directory = temporaryDirectory()

    #expect(state(in: directory, windows: []).activeUntil(now: local(10, 20, 23, 0)) == nil)
  }

  @Test func aSnoozeAloneStillCounts() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = local(10, 20, 12, 0)
    let quiet = state(in: directory, windows: weeknights)
    try quiet.quietTime.quiet(until: now.addingTimeInterval(600))

    #expect(quiet.activeUntil(now: now) == now.addingTimeInterval(600))
  }

  @Test func aSnoozeInsideAWindowDoesNotShortenIt() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = local(10, 20, 23, 0)
    let quiet = state(in: directory, windows: weeknights)
    try quiet.quietTime.quiet(until: now.addingTimeInterval(600))

    #expect(quiet.activeUntil(now: now) == local(10, 21, 9, 0))
  }

  @Test func aSnoozeEndingAfterTheWindowExtendsQuietTime() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = local(10, 21, 8, 30)
    let quiet = state(in: directory, windows: weeknights)
    try quiet.quietTime.quiet(until: now.addingTimeInterval(3600))

    #expect(quiet.activeUntil(now: now) == now.addingTimeInterval(3600))
  }

  @Test func endNowClearsTheSnoozeAndSkipsTheRunningWindow() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = local(10, 20, 23, 0)
    let quiet = state(in: directory, windows: weeknights)
    try quiet.quietTime.quiet(until: now.addingTimeInterval(600))

    try quiet.endNow(now: now)

    #expect(quiet.activeUntil(now: now) == nil)
    #expect(quiet.activeUntil(now: local(10, 21, 8, 0)) == nil)
    #expect(quiet.skippedWindow.activeUntil(now: now) == local(10, 21, 9, 0))
  }

  @Test func theSkipLapsesForTheNextOccurrence() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let quiet = state(in: directory, windows: weeknights)
    try quiet.endNow(now: local(10, 20, 23, 0))

    #expect(quiet.activeUntil(now: local(10, 21, 19, 30)) == local(10, 22, 9, 0))
  }

  @Test func endNowWithoutAWindowWritesNoSkip() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = local(10, 20, 12, 0)
    let quiet = state(in: directory, windows: weeknights)
    try quiet.quietTime.quiet(until: now.addingTimeInterval(600))

    try quiet.endNow(now: now)

    #expect(quiet.activeUntil(now: now) == nil)
    #expect(
      !FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("quiet-hours-skipped-until").path))
  }

  @Test func aSnoozeAfterSkippingAWindowIsQuietOnItsOwn() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = local(10, 20, 23, 0)
    let quiet = state(in: directory, windows: weeknights)
    try quiet.endNow(now: now)
    try quiet.quietTime.quiet(until: now.addingTimeInterval(600))

    #expect(quiet.activeUntil(now: now) == now.addingTimeInterval(600))
  }

  @Test func windowEndNamesOnlyAnUnskippedWindow() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = local(10, 20, 23, 0)
    let quiet = state(in: directory, windows: weeknights)

    #expect(quiet.windowEnd(now: now) == local(10, 21, 9, 0))
    try quiet.endNow(now: now)
    #expect(quiet.windowEnd(now: now) == nil)
  }
}

@Suite struct QuietHoursConfigTests {
  private func parse(_ json: String) -> (file: ConfigFile, logLines: [String]) {
    ConfigFileParser.parse(Data(json.utf8))
  }

  @Test func parsesGoodEntries() throws {
    let (file, logLines) = parse(
      """
      { "quietHours": [
        { "days": ["mon", "tue", "wed", "thu", "fri"], "from": "19:00", "to": "09:00" },
        { "days": ["sun", "sat"], "from": "00:00", "to": "12:30" }
      ] }
      """)

    #expect(logLines.isEmpty)
    #expect(file.quietHours?.count == 2)
    #expect(file.quietHours?.first?.days == [.mon, .tue, .wed, .thu, .fri])
    #expect(file.quietHours?.first?.fromMinute == 19 * 60)
    #expect(file.quietHours?.first?.toMinute == 9 * 60)
    #expect(file.quietHours?.last?.days == [.sat, .sun])
    #expect(file.quietHours?.last?.toMinute == 12 * 60 + 30)
  }

  @Test func dropsBadEntriesWithOneLineEachAndKeepsTheRest() throws {
    let (file, logLines) = parse(
      """
      { "quietHours": [
        { "days": ["mon"], "from": "19:00", "to": "09:00" },
        { "days": ["mon"], "from": "25:00", "to": "09:00" },
        { "days": [], "from": "19:00", "to": "09:00" },
        { "days": ["mon"], "from": "09:00", "to": "09:00" },
        { "days": ["monday"], "from": "19:00", "to": "09:00" },
        { "days": ["tue"], "from": "19:00" },
        "nonsense",
        { "days": ["fri"], "from": "22:00", "to": "06:00" }
      ] }
      """)

    #expect(file.quietHours?.map(\.title) == ["Mon 19:00–09:00", "Fri 22:00–06:00"])
    #expect(logLines.count == 6)
    #expect(logLines.allSatisfy { $0.hasPrefix("quietHours[") })
  }

  @Test func dropsEntriesBeyondSeven() throws {
    let entry = #"{ "days": ["mon"], "from": "19:00", "to": "09:00" }"#
    let (file, logLines) = parse(
      "{ \"quietHours\": [\(Array(repeating: entry, count: 8).joined(separator: ","))] }")

    #expect(file.quietHours?.count == 7)
    #expect(logLines == ["quietHours[7]: at most 7 windows, dropped"])
  }

  @Test func aNonArrayFallsBackToNoWindows() throws {
    let (file, logLines) = parse(#"{ "quietHours": "nights" }"#)

    #expect(file.quietHours == nil)
    #expect(logLines == ["quietHours: not an array, using default []"])
  }

  @Test func unknownKeysInAnEntryAreLoggedAndTheEntryStillApplies() throws {
    let (file, logLines) = parse(
      #"{ "quietHours": [{ "days": ["mon"], "from": "19:00", "to": "09:00", "tz": "x" }] }"#)

    #expect(file.quietHours?.count == 1)
    #expect(logLines == ["unknown key \"quietHours[0].tz\", ignored"])
  }

  @Test func quietHoursIsNotAHostKey() throws {
    let (_, logLines) = parse(
      #"{ "hosts": { "claude": { "quietHours": [] } } }"#)

    #expect(logLines == ["unknown key \"hosts.claude.quietHours\", ignored"])
  }

  @Test func settingsCarryTheWindowsForEveryHost() throws {
    let (file, _) = parse(
      #"{ "quietHours": [{ "days": ["mon"], "from": "19:00", "to": "09:00" }] }"#)

    #expect(Settings.resolve(file: file, host: .codex).quietHours == file.quietHours)
    #expect(Settings.resolve(file: ConfigFile(), host: .claude).quietHours.isEmpty)
    #expect(file.quietSchedule.windows == file.quietHours)
  }

  @Test func editingWritesWindowsThatParseBack() throws {
    let windows = [
      QuietWindow(days: [.mon, .tue], from: "19:00", to: "09:00"),
      QuietWindow(days: [.sun], from: "00:00", to: "12:00"),
    ].compactMap { $0 }

    let bytes = try ConfigEdit.applying([.quietHours(windows)], to: nil)
    let (file, logLines) = ConfigFileParser.parse(Data(bytes))

    #expect(logLines.isEmpty)
    #expect(file.quietHours == windows)
  }

  @Test func editingToNoWindowsWritesAnEmptyList() throws {
    let windows = [QuietWindow(days: [.mon], from: "19:00", to: "09:00")].compactMap { $0 }
    let first = try ConfigEdit.applying([.quietHours(windows)], to: nil)

    let second = try ConfigEdit.applying([.quietHours([])], to: first)

    #expect(ConfigFileParser.parse(Data(second)).file.quietHours == [])
  }

  @Test func resetRemovesTheKey() throws {
    let windows = [QuietWindow(days: [.mon], from: "19:00", to: "09:00")].compactMap { $0 }
    let first = try ConfigEdit.applying([.quietHours(windows)], to: nil)

    let second = try ConfigEdit.applying([.reset(.quietHours)], to: first)

    #expect(ConfigFileParser.parse(Data(second)).file.quietHours == nil)
  }

  @Test func preferenceValuesFollowEditsAndReset() throws {
    let windows = [QuietWindow(days: [.mon], from: "19:00", to: "09:00")].compactMap { $0 }

    let edited = PreferenceValues().applying(.quietHours(windows))

    #expect(edited.quietHours == windows)
    #expect(edited.applying(.reset(.quietHours)).quietHours.isEmpty)
    #expect(PreferenceValues(file: ConfigFile(quietHours: windows)).quietHours == windows)
  }

  @Test func resetSeesAChangeOnlyWhenWindowsExist() throws {
    let windows = [QuietWindow(days: [.mon], from: "19:00", to: "09:00")].compactMap { $0 }

    #expect(PreferenceReset.isChanged(.quietHours, in: ConfigFile(quietHours: windows)))
    #expect(!PreferenceReset.isChanged(.quietHours, in: ConfigFile(quietHours: [])))
    #expect(!PreferenceReset.isChanged(.quietHours, in: ConfigFile()))
    #expect(SettingsPane.panels.preferenceNames.contains(.quietHours))
  }

  @Test func addingAWindowValidatesDaysThenTimes() throws {
    let existing = [QuietWindow(days: [.mon], from: "19:00", to: "09:00")].compactMap { $0 }

    #expect(
      PreferenceRules.quietWindow(days: [], from: "19:00", to: "09:00", joining: existing)
        == .failure(.noDays))
    #expect(
      PreferenceRules.quietWindow(days: [.mon], from: "7pm", to: "09:00", joining: existing)
        == .failure(.badTimes))
    #expect(
      PreferenceRules.quietWindow(days: [.mon], from: "19:00", to: "19:00", joining: existing)
        == .failure(.badTimes))
    #expect(
      PreferenceRules.quietWindow(days: [.mon], from: "19:00", to: "09:00", joining: existing)
        == .failure(.duplicate))
    #expect(
      PreferenceRules.quietWindow(days: [.tue], from: " 19:00", to: "09:00 ", joining: existing)
        == .success(
          QuietWindow(days: [.tue], fromMinute: 19 * 60, toMinute: 9 * 60)
            ?? existing[0]))
  }

  @Test func addingAWindowStopsAtSeven() throws {
    let existing = QuietWeekday.allCases.compactMap {
      QuietWindow(days: [$0], from: "19:00", to: "09:00")
    }

    #expect(
      PreferenceRules.quietWindow(days: [.mon], from: "01:00", to: "02:00", joining: existing)
        == .failure(.full))
  }

  @Test func theBadInputMessagesAreTheAgreedText() throws {
    #expect(QuietWindowError.noDays.description == "Pick at least one day")
    #expect(
      QuietWindowError.badTimes.description == "Enter a start and end time, like 19:00")
  }

  @Test func theRowHasItsOwnTitleAndCaption() throws {
    #expect(PreferenceName.quietHours.title == "Quiet hours")
    #expect(!PreferenceName.quietHours.caption.isEmpty)
    #expect(!PreferenceName.quietHours.explanation.isEmpty)
    #expect(PreferenceName.quietHours.defaultText == "No windows")
    #expect(PreferenceName.quietHours.keyPath == ["quietHours"])
  }
}
