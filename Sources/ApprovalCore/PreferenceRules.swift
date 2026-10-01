import Foundation

public enum SnoozeTextError: Error, Sendable, Equatable, CustomStringConvertible {
  case empty
  case notADuration(String)
  case outOfRange(TimeInterval)
  case tooMany(Int)

  public var description: String {
    switch self {
    case .empty:
      return "Enter 1 to 6 presets, like 30s, 5, 15m, 1h (a bare number is minutes)"
    case .notADuration(let word):
      return "\"\(word)\" isn't a duration"
    case .outOfRange(let seconds):
      return
        "\(DurationText.compact(seconds)) is outside"
        + " \(DurationText.compact(Settings.snoozePresetRange.lowerBound)) to"
        + " \(DurationText.compact(Settings.snoozePresetRange.upperBound))"
    case .tooMany(let count):
      return "\(count) presets, at most 6 fit the menu"
    }
  }
}

public struct DurationFieldSpec: Sendable, Equatable {
  public let bareUnit: TimeInterval
  public let range: ClosedRange<TimeInterval>
}

extension PreferenceName {
  public var durationField: DurationFieldSpec? {
    switch self {
    case .idleSeconds:
      return DurationFieldSpec(bareUnit: 1, range: Settings.idleSecondsRange)
    case .graceSeconds:
      return DurationFieldSpec(bareUnit: 1, range: Settings.graceSecondsRange)
    case .armDelay, .chainedArmDelay:
      return DurationFieldSpec(bareUnit: 1, range: Settings.armDelayRange)
    case .waitingNoticeMinutes:
      return DurationFieldSpec(bareUnit: 60, range: Settings.waitingNoticeDelayRange)
    default:
      return nil
    }
  }
}

public enum DurationFieldError: Error, Sendable, Equatable, CustomStringConvertible {
  case empty(bareUnit: TimeInterval)
  case notADuration(String)
  case outOfRange(TimeInterval, ClosedRange<TimeInterval>)

  public var description: String {
    switch self {
    case .empty(let bareUnit):
      if bareUnit == 60 {
        return "Enter a duration, like 90s, 5 or 1h (a bare number is minutes)"
      }
      return "Enter a duration, like 500ms, 5s or 2m (a bare number is seconds)"
    case .notADuration(let word):
      return "\"\(word)\" isn't a duration"
    case .outOfRange(let seconds, let range):
      return
        "\(DurationText.compact(seconds)) is outside"
        + " \(DurationText.compact(range.lowerBound)) to \(DurationText.compact(range.upperBound))"
    }
  }
}

public enum HandoffAppError: Error, Sendable, Equatable, CustomStringConvertible {
  case empty
  case containsWhitespace
  case duplicate(String)

  public var description: String {
    switch self {
    case .empty:
      return "Enter a bundle ID, like com.openai.codex"
    case .containsWhitespace:
      return "A bundle ID has no spaces"
    case .duplicate(let bundleID):
      return "\(bundleID) is already in the list"
    }
  }
}

public enum QuietWindowError: Error, Sendable, Equatable, CustomStringConvertible {
  case noDays
  case badTimes
  case duplicate
  case full

  public var description: String {
    switch self {
    case .noDays:
      return "Pick at least one day"
    case .badTimes:
      return "Enter a time like 9, 0930 or 21:30."
    case .duplicate:
      return "That window is already in the list"
    case .full:
      return "At most \(QuietWindow.maximumCount) windows"
    }
  }
}

public enum PreferenceRules {
  public static let armDelayRange = Settings.armDelayRange
  public static let armDelayStepsPerSecond: Double = 10
  public static let idleSecondsRange = Settings.idleSecondsRange
  public static let graceSecondsRange = Settings.graceSecondsRange
  public static let snoozePresetCount: ClosedRange<Int> = 1...6

  public static func armDelay(_ value: Double) -> Double {
    thousandths(clamp(value, to: armDelayRange))
  }

  public static func sliderArmDelay(_ value: Double) -> Double {
    (clamp(value, to: armDelayRange) * armDelayStepsPerSecond).rounded()
      / armDelayStepsPerSecond
  }

  public static func thousandths(_ value: Double) -> Double {
    (value * 1000).rounded() / 1000
  }

  public static func chainedArmDelay(_ value: Double) -> Double {
    armDelay(value)
  }

  public static func idleSeconds(_ value: Double) -> Double {
    clamp(value, to: idleSecondsRange)
  }

  public static func graceSeconds(_ value: Double) -> Double {
    clamp(value, to: graceSecondsRange)
  }

  public static func snoozePresets(from text: String) -> Result<[TimeInterval], SnoozeTextError> {
    let words = text.split { $0 == "," || $0.isWhitespace }.map(String.init)
    guard !words.isEmpty else { return .failure(.empty) }
    var presets: [TimeInterval] = []
    for word in words {
      guard let seconds = DurationText.parse(word, bareUnit: 60) else {
        return .failure(.notADuration(word))
      }
      guard Settings.snoozePresetRange.contains(seconds) else {
        return .failure(.outOfRange(seconds))
      }
      presets.append(seconds)
    }
    guard snoozePresetCount.contains(presets.count) else {
      return .failure(.tooMany(presets.count))
    }
    return .success(presets)
  }

  public static func snoozeText(_ presets: [TimeInterval]) -> String {
    presets.map(minutesWord).joined(separator: ", ")
  }

  public static func snoozeListText(_ presets: [TimeInterval]) -> String {
    let wholeMinutes = presets.compactMap { seconds -> Int? in
      Int(exactly: seconds / 60).flatMap { $0 * 60 == Int(seconds) ? $0 : nil }
    }
    guard wholeMinutes.count == presets.count else {
      return presets.map(DurationText.compact).joined(separator: ", ")
    }
    let words = wholeMinutes.map(String.init)
    let joined: String
    if words.count > 1, let last = words.last {
      joined = "\(words.dropLast().joined(separator: ", ")) and \(last)"
    } else {
      joined = words.first ?? ""
    }
    return "\(joined) minute\(wholeMinutes == [1] ? "" : "s")"
  }

  private static func minutesWord(_ seconds: TimeInterval) -> String {
    let minutes = seconds / 60
    guard minutes.truncatingRemainder(dividingBy: 1) == 0, let whole = Int(exactly: minutes) else {
      return DurationText.compact(seconds)
    }
    return String(whole)
  }

  public static func handoffApp(_ text: String, joining existing: [String])
    -> Result<String, HandoffAppError>
  {
    let bundleID = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !bundleID.isEmpty else { return .failure(.empty) }
    guard !bundleID.contains(where: \.isWhitespace) else { return .failure(.containsWhitespace) }
    guard !existing.contains(bundleID) else { return .failure(.duplicate(bundleID)) }
    return .success(bundleID)
  }

  public static func quietWindow(
    days: [QuietWeekday], from: String, to: String, joining existing: [QuietWindow]
  ) -> Result<QuietWindow, QuietWindowError> {
    guard !days.isEmpty else { return .failure(.noDays) }
    guard
      let window = QuietWindow(
        days: days, from: from.trimmingCharacters(in: .whitespaces),
        to: to.trimmingCharacters(in: .whitespaces))
    else { return .failure(.badTimes) }
    guard !existing.contains(window) else { return .failure(.duplicate) }
    guard existing.count < QuietWindow.maximumCount else { return .failure(.full) }
    return .success(window)
  }

  public static func minutesText(_ minutes: Int) -> String {
    "\(minutes) minute\(minutes == 1 ? "" : "s")"
  }

  public static func duration(from text: String, spec: DurationFieldSpec)
    -> Result<TimeInterval, DurationFieldError>
  {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .failure(.empty(bareUnit: spec.bareUnit)) }
    guard let seconds = DurationText.parse(trimmed, bareUnit: spec.bareUnit) else {
      return .failure(.notADuration(trimmed))
    }
    guard spec.range.contains(seconds) else { return .failure(.outOfRange(seconds, spec.range)) }
    return .success(thousandths(seconds))
  }

  public static func secondsText(_ value: Double) -> String {
    "\(numberText(value)) s"
  }

  public static func numberText(_ value: Double) -> String {
    let rounded = thousandths(value)
    guard let integer = Int(exactly: rounded) else { return String(rounded) }
    return String(integer)
  }

  private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
