import Foundation

public struct QuietState: Sendable {
  public let quietTime: QuietTime
  public let skippedWindow: QuietTime
  public let schedule: QuietSchedule
  public let calendar: Calendar

  public init(
    quietTime: QuietTime, skippedWindowFile: URL, schedule: QuietSchedule,
    calendar: Calendar = .current
  ) {
    self.quietTime = quietTime
    self.skippedWindow = QuietTime(file: skippedWindowFile)
    self.schedule = schedule
    self.calendar = calendar
  }

  public init(paths: AppPaths, schedule: QuietSchedule) {
    self.init(
      quietTime: QuietTime(file: paths.quietFile), skippedWindowFile: paths.quietHoursSkippedFile,
      schedule: schedule)
  }

  public init(paths: AppPaths) {
    self.init(paths: paths, schedule: ConfigFileLoader.load(paths: paths).file.quietSchedule)
  }

  public func activeUntil(now: Date = Date()) -> Date? {
    let snoozeEnd = quietTime.activeUntil(now: now)
    let windowEnd = unskippedWindow(now: now)?.end
    switch (snoozeEnd, windowEnd) {
    case (let snooze?, let window?): return max(snooze, window)
    case (let snooze?, nil): return snooze
    case (nil, let window?): return window
    case (nil, nil): return nil
    }
  }

  public func endNow(now: Date = Date()) throws {
    try quietTime.clear()
    if let window = unskippedWindow(now: now) {
      try skippedWindow.quiet(until: window.end)
    }
  }

  public func windowEnd(now: Date = Date()) -> Date? {
    unskippedWindow(now: now)?.end
  }

  private func unskippedWindow(now: Date) -> (start: Date, end: Date)? {
    guard let window = schedule.activeWindow(at: now, calendar: calendar) else { return nil }
    if let skippedEnd = skippedWindow.activeUntil(now: now), window.end <= skippedEnd {
      return nil
    }
    return window
  }
}
