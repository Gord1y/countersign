import Foundation

public enum UpdateCheckCommandText {
  public static let usage = "usage: countersign update-check"

  public static func lines(
    outcome: UpdateCheckOutcome, currentVersion: String, availability: UpdateAvailability?
  ) -> [String] {
    switch outcome {
    case .upToDate:
      return ["up to date (\(currentVersion))"]
    case .newerAvailable(let version):
      var lines = ["update available: \(version)"]
      if let availability {
        lines.append("upgrade: \(availability.upgradeCommand)")
        if let url = availability.releaseNotesURL {
          lines.append("release notes: \(url.absoluteString)")
        }
      }
      return lines
    case .unknown(let reason):
      return ["error: could not check for updates: \(reason)"]
    }
  }

  public static func succeeded(_ outcome: UpdateCheckOutcome) -> Bool {
    if case .unknown = outcome { return false }
    return true
  }
}

public enum ContextCommandText {
  public static let usage = "usage: countersign context"
  public static let checkpointsOff = "context checkpoints are off"
  public static let noSessions = "no live sessions"
}
