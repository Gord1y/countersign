import Foundation

public enum KeepAwakeDuration: String, CaseIterable, Sendable {
  case oneHour = "1h"
  case fourHours = "4h"
  case eightHours = "8h"
  case twelveHours = "12h"
  case untilTurnedOff = "forever"

  public var seconds: TimeInterval? {
    switch self {
    case .oneHour: return 3600
    case .fourHours: return 14400
    case .eightHours: return 28800
    case .twelveHours: return 43200
    case .untilTurnedOff: return nil
    }
  }

  public var settingsTitle: String {
    switch self {
    case .oneHour: return "1 hour"
    case .fourHours: return "4 hours"
    case .eightHours: return "8 hours"
    case .twelveHours: return "12 hours"
    case .untilTurnedOff: return "Until I turn it off"
    }
  }

  public var menuTitle: String {
    switch self {
    case .oneHour: return "For 1 Hour"
    case .fourHours: return "For 4 Hours"
    case .eightHours: return "For 8 Hours"
    case .twelveHours: return "For 12 Hours"
    case .untilTurnedOff: return "Until I Turn It Off"
    }
  }

  public func end(from now: Date) -> KeepAwakeEnd {
    guard let seconds else { return .untilTurnedOff }
    return .at(now.addingTimeInterval(seconds))
  }
}

public enum KeepAwakeEnd: Sendable, Equatable {
  case at(Date)
  case untilTurnedOff
}

public enum KeepAwakePower: Sendable, Equatable {
  case pluggedIn
  case noBattery
  case battery(percent: Int)

  public init(internalBatteryState state: String?, capacity: Int?, maxCapacity: Int?) {
    switch state {
    case "AC Power":
      self = .pluggedIn
    case "Battery Power":
      guard let capacity, let maxCapacity, maxCapacity > 0, capacity >= 0 else {
        self = .noBattery
        return
      }
      let percent = (Double(capacity) / Double(maxCapacity) * 100).rounded()
      self = .battery(percent: Int(min(max(percent, 0), 100)))
    default:
      self = .noBattery
    }
  }
}

public enum KeepAwakeState: Sendable, Equatable {
  case notRunning
  case holding(KeepAwakeEnd)
  case releasedAtCutoff(KeepAwakeEnd, cutoff: Int)

  public var isRunning: Bool {
    self != .notRunning
  }

  public var holdsIdleSleep: Bool {
    if case .holding = self { return true }
    return false
  }

  public var end: KeepAwakeEnd? {
    switch self {
    case .notRunning: return nil
    case .holding(let end): return end
    case .releasedAtCutoff(let end, _): return end
    }
  }

  public var statusTitle: String {
    switch self {
    case .notRunning: return "Not running"
    case .holding: return "Keeping this Mac awake"
    case .releasedAtCutoff(_, let cutoff): return "Released at \(cutoff)% battery"
    }
  }

  public func statusCaption(timeZone: TimeZone = .current) -> String {
    switch self {
    case .notRunning:
      return "Start it here or from the menu bar."
    case .holding(.at(let date)):
      return
        "Until \(TimeOfDayText.describe(date, timeZone: timeZone))."
        + " The display still turns off and locks."
    case .holding(.untilTurnedOff):
      return "Until you turn it off. The display still turns off and locks."
    case .releasedAtCutoff(.at(let date), _):
      return
        "Holds again if you plug in, until \(TimeOfDayText.describe(date, timeZone: timeZone))."
    case .releasedAtCutoff(.untilTurnedOff, _):
      return "Holds again if you plug in."
    }
  }
}

public enum KeepAwakePolicy {
  public static func state(
    optedIn: Bool, session: KeepAwakeEnd?, power: KeepAwakePower, cutoff: Int
  ) -> KeepAwakeState {
    guard optedIn, let session else { return .notRunning }
    if case .battery(let percent) = power, percent <= cutoff {
      return .releasedAtCutoff(session, cutoff: cutoff)
    }
    return .holding(session)
  }
}
