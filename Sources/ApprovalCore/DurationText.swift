import Foundation

public enum DurationText {
  public static func parse(_ text: String) -> TimeInterval? {
    guard let seconds = parse(text, bareUnit: 60), seconds > 0 else { return nil }
    return seconds
  }

  public static func snoozeSeconds(_ text: String) -> TimeInterval? {
    guard let seconds = parse(text), Settings.snoozePresetRange.contains(seconds) else {
      return nil
    }
    return seconds
  }

  public static func parse(_ text: String, bareUnit: TimeInterval) -> TimeInterval? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()

    let unitMultipliers: [(suffix: String, multiplier: TimeInterval)] = [
      ("ms", 0.001), ("h", 3600), ("m", 60), ("s", 1),
    ]
    for unit in unitMultipliers {
      guard lower.hasSuffix(unit.suffix) else { continue }
      let numberText = String(lower.dropLast(unit.suffix.count))
      guard let value = number(numberText) else { return nil }
      return value * unit.multiplier
    }

    guard let value = number(lower) else { return nil }
    return value * bareUnit
  }

  public static func compact(_ seconds: TimeInterval) -> String {
    let milliseconds = (seconds * 1000).rounded()
    if milliseconds == 0 { return "0s" }
    if milliseconds < 1000 { return "\(numberText(milliseconds))ms" }
    let rounded = milliseconds / 1000
    if rounded.truncatingRemainder(dividingBy: 3600) == 0 {
      return "\(numberText(rounded / 3600))h"
    }
    if rounded.truncatingRemainder(dividingBy: 60) == 0 {
      return "\(numberText(rounded / 60))m"
    }
    return "\(numberText(rounded))s"
  }

  public static func describe(_ seconds: TimeInterval) -> String {
    let rounded = seconds.rounded()
    guard rounded >= 1 else { return "0 seconds" }
    guard let totalSeconds = Int64(exactly: rounded) else { return compact(seconds) }

    if totalSeconds % 3600 == 0 {
      let hours = totalSeconds / 3600
      return "\(hours) hour\(hours == 1 ? "" : "s")"
    }
    if totalSeconds >= 60 {
      let minutes = Int64((Double(totalSeconds) / 60).rounded())
      return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
    return "\(totalSeconds) second\(totalSeconds == 1 ? "" : "s")"
  }

  private static func number(_ text: String) -> Double? {
    guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
    return value
  }

  private static func numberText(_ value: Double) -> String {
    let thousandths = (value * 1000).rounded() / 1000
    if thousandths.truncatingRemainder(dividingBy: 1) == 0, let whole = Int64(exactly: thousandths)
    {
      return String(whole)
    }
    return String(thousandths)
  }
}
