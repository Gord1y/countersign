import Foundation

public enum HeaderControlTint: Sendable, Equatable {
  case secondary
  case yellow
  case amber
  case blue
}

public struct SettingsHeaderControls: Sendable, Equatable {
  public let status: CountersignStatus

  public init(status: CountersignStatus) {
    self.status = status
  }

  public var isPaused: Bool {
    switch status {
    case .paused, .pausedUntilAppOpens: return true
    case .active, .quiet: return false
    }
  }

  public var quietUntil: Date? {
    guard case .quiet(let until) = status else { return nil }
    return until
  }

  public var pauseTint: HeaderControlTint {
    isPaused ? .yellow : .secondary
  }

  public var pauseAccessibilityValue: String {
    isPaused ? "Paused" : "Not paused"
  }

  public var pauseHelp: String {
    isPaused ? "Resume Countersign" : "Pause Countersign"
  }

  public var snoozeTint: HeaderControlTint {
    quietUntil == nil ? .secondary : .blue
  }

  public var snoozeIsEnabled: Bool {
    !isPaused
  }

  public var snoozeHelp: String {
    quietUntil == nil ? "Snooze Countersign" : "Quiet time"
  }

  public func caption(timeZone: TimeZone = .current) -> (text: String, tint: HeaderControlTint)? {
    switch status {
    case .active:
      return nil
    case .paused:
      return ("Paused", .amber)
    case .pausedUntilAppOpens:
      return ("Paused until Countersign opens", .amber)
    case .quiet(let until):
      return ("Until \(TimeOfDayText.describe(until, timeZone: timeZone))", .blue)
    }
  }

  public func quietHeading(timeZone: TimeZone = .current) -> String? {
    quietUntil.map { "Quiet until \(TimeOfDayText.describe($0, timeZone: timeZone))" }
  }
}
