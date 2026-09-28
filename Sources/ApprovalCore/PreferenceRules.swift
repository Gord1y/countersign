import Foundation

public enum SnoozeTextError: Error, Sendable, Equatable, CustomStringConvertible {
  case empty
  case notAWholeNumber(String)
  case outOfRange(Int)
  case tooMany(Int)

  public var description: String {
    switch self {
    case .empty:
      return "Enter 1 to 6 presets in minutes, like 1, 5, 15, 30"
    case .notAWholeNumber(let word):
      return "\"\(word)\" is not a whole number of minutes"
    case .outOfRange(let minutes):
      return "\(minutes) is outside 1 to 1440 minutes"
    case .tooMany(let count):
      return "\(count) presets, at most 6 fit the menu"
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

public enum PreferenceRules {
  public static let armDelayRange = Settings.armDelayRange
  public static let armDelayStepsPerSecond: Double = 10
  public static let idleSecondsRange: ClosedRange<Double> = 1...30
  public static let graceSecondsRange: ClosedRange<Double> = 0...30
  public static let snoozePresetCount: ClosedRange<Int> = 1...6
  public static let snoozeMinuteRange: ClosedRange<Int> = 1...1440

  public static func armDelay(_ value: Double) -> Double {
    (clamp(value, to: armDelayRange) * armDelayStepsPerSecond).rounded()
      / armDelayStepsPerSecond
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

  public static func snoozeMinutes(from text: String) -> Result<[Int], SnoozeTextError> {
    let words = text.split { $0 == "," || $0.isWhitespace }.map(String.init)
    guard !words.isEmpty else { return .failure(.empty) }
    var minutes: [Int] = []
    for word in words {
      guard let value = Int(word) else { return .failure(.notAWholeNumber(word)) }
      guard snoozeMinuteRange.contains(value) else { return .failure(.outOfRange(value)) }
      minutes.append(value)
    }
    guard snoozePresetCount.contains(minutes.count) else {
      return .failure(.tooMany(minutes.count))
    }
    return .success(minutes)
  }

  public static func snoozeText(_ minutes: [Int]) -> String {
    minutes.map(String.init).joined(separator: ", ")
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

  public static func secondsText(_ value: Double) -> String {
    "\(numberText(value)) s"
  }

  public static func numberText(_ value: Double) -> String {
    guard let integer = Int(exactly: value) else { return String(value) }
    return String(integer)
  }

  private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
