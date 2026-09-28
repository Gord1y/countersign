import Foundation

public enum DurationText {
  public static func parse(_ text: String) -> TimeInterval? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()

    let unitMultipliers: [(suffix: String, multiplier: TimeInterval)] = [
      ("h", 3600), ("m", 60), ("s", 1),
    ]
    for unit in unitMultipliers {
      guard lower.hasSuffix(unit.suffix) else { continue }
      let numberText = String(lower.dropLast(unit.suffix.count))
      guard let value = Double(numberText), value > 0 else { return nil }
      return value * unit.multiplier
    }

    guard let value = Double(lower), value > 0 else { return nil }
    return value * 60
  }

  public static func describe(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int64(seconds.rounded())
    guard totalSeconds > 0 else { return "0 seconds" }

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
}
