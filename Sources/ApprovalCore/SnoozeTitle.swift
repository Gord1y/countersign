import Foundation

public enum SnoozeTitle {
  public static func describe(minutes: Int, isFirst: Bool) -> String {
    let duration = DurationText.describe(TimeInterval(minutes * 60))
    return isFirst ? "Quiet for \(duration)" : duration
  }
}
