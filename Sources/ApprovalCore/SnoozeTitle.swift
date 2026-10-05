import Foundation

public enum SnoozeTitle {
  public static func describe(seconds: TimeInterval, isFirst: Bool) -> String {
    let duration = durationText(seconds)
    return isFirst ? "Quiet for \(duration)" : duration
  }

  private static func durationText(_ seconds: TimeInterval) -> String {
    let whole = Int64(seconds.rounded())
    guard whole > 60, whole % 60 != 0 else { return DurationText.describe(seconds) }
    return "\(whole) seconds"
  }
}
