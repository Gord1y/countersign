import Foundation

public enum QuietWeekday: String, Sendable, Hashable, CaseIterable {
  case mon
  case tue
  case wed
  case thu
  case fri
  case sat
  case sun

  public var calendarWeekday: Int {
    switch self {
    case .sun: return 1
    case .mon: return 2
    case .tue: return 3
    case .wed: return 4
    case .thu: return 5
    case .fri: return 6
    case .sat: return 7
    }
  }

  public var title: String {
    rawValue.capitalized
  }

  public var initial: String {
    switch self {
    case .mon: return "M"
    case .tue: return "T"
    case .wed: return "W"
    case .thu: return "T"
    case .fri: return "F"
    case .sat: return "S"
    case .sun: return "S"
    }
  }
}

public struct QuietWindow: Sendable, Hashable {
  public static let maximumCount = 7

  public let days: [QuietWeekday]
  public let fromMinute: Int
  public let toMinute: Int

  public init?(days: [QuietWeekday], fromMinute: Int, toMinute: Int) {
    let ordered = QuietWeekday.allCases.filter { days.contains($0) }
    guard !ordered.isEmpty,
      QuietWindow.minuteRange.contains(fromMinute),
      QuietWindow.minuteRange.contains(toMinute),
      fromMinute != toMinute
    else { return nil }
    self.days = ordered
    self.fromMinute = fromMinute
    self.toMinute = toMinute
  }

  public init?(days: [QuietWeekday], from: String, to: String) {
    guard let fromMinute = QuietWindow.minute(from: from),
      let toMinute = QuietWindow.minute(from: to)
    else { return nil }
    self.init(days: days, fromMinute: fromMinute, toMinute: toMinute)
  }

  private static let minuteRange = 0..<(24 * 60)

  public static func minute(from text: String) -> Int? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ":") }) else { return nil }
    let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
    let hourText: Substring
    let minuteText: Substring
    switch parts.count {
    case 1:
      let digits = parts[0]
      switch digits.count {
      case 1, 2:
        hourText = digits
        minuteText = "0"
      case 3, 4:
        hourText = digits.dropLast(2)
        minuteText = digits.suffix(2)
      default:
        return nil
      }
    case 2:
      guard (1...2).contains(parts[0].count), parts[1].count == 2 else { return nil }
      hourText = parts[0]
      minuteText = parts[1]
    default:
      return nil
    }
    guard let hour = Int(hourText), let minute = Int(minuteText),
      (0..<24).contains(hour), (0..<60).contains(minute)
    else { return nil }
    return hour * 60 + minute
  }

  public static func text(ofMinute minute: Int) -> String {
    String(format: "%02d:%02d", minute / 60, minute % 60)
  }

  public var fromText: String {
    QuietWindow.text(ofMinute: fromMinute)
  }

  public var toText: String {
    QuietWindow.text(ofMinute: toMinute)
  }

  public var runsPastMidnight: Bool {
    toMinute < fromMinute
  }

  public var dayText: String {
    let all = QuietWeekday.allCases
    var runs: [[QuietWeekday]] = []
    for day in days {
      if let last = runs.last?.last,
        let lastIndex = all.firstIndex(of: last),
        all.firstIndex(of: day) == lastIndex + 1
      {
        runs[runs.count - 1].append(day)
      } else {
        runs.append([day])
      }
    }
    return runs.map { run in
      guard run.count >= 3, let first = run.first, let last = run.last else {
        return run.map(\.title).joined(separator: ", ")
      }
      return "\(first.title)–\(last.title)"
    }.joined(separator: ", ")
  }

  public var title: String {
    "\(dayText) \(fromText)–\(toText)"
  }
}

public struct QuietSchedule: Sendable, Equatable {
  public let windows: [QuietWindow]

  public init(windows: [QuietWindow]) {
    self.windows = windows
  }

  public func activeWindow(at now: Date, calendar: Calendar = .current) -> (
    start: Date, end: Date
  )? {
    let today = calendar.startOfDay(for: now)
    var occurrences: [(start: Date, end: Date)] = []
    for offset in -1...QuietSchedule.mergeHorizonDays {
      guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
      for window in windows {
        if let found = occurrence(of: window, startingOn: day, calendar: calendar) {
          occurrences.append(found)
        }
      }
    }
    let running = occurrences.filter { $0.start <= now && now < $0.end }
    guard let first = running.min(by: { $0.start < $1.start }) else { return nil }
    var run = (start: first.start, end: running.map(\.end).max() ?? first.end)
    var extended = true
    while extended {
      extended = false
      for candidate in occurrences where candidate.start <= run.end && candidate.end > run.end {
        run.end = candidate.end
        extended = true
      }
    }
    return run
  }

  private static let mergeHorizonDays = 7

  private func occurrence(
    of window: QuietWindow, startingOn day: Date, calendar: Calendar
  ) -> (start: Date, end: Date)? {
    let weekday = calendar.component(.weekday, from: day)
    guard window.days.contains(where: { $0.calendarWeekday == weekday }) else { return nil }
    let endDay =
      window.runsPastMidnight ? calendar.date(byAdding: .day, value: 1, to: day) : day
    guard let endDay,
      let start = time(ofMinute: window.fromMinute, on: day, calendar: calendar),
      let end = time(ofMinute: window.toMinute, on: endDay, calendar: calendar)
    else { return nil }
    return (start, end)
  }

  private func time(ofMinute minute: Int, on day: Date, calendar: Calendar) -> Date? {
    calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
  }
}
