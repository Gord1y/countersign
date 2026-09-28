import Foundation

public enum CountersignStatusAction: Sendable, Equatable {
  case pause
  case resume
  case endQuietTime

  public var title: String {
    switch self {
    case .pause: return "Pause"
    case .resume: return "Resume"
    case .endQuietTime: return "End now"
    }
  }
}

public enum CountersignStatus: Sendable, Equatable {
  case active
  case paused
  case pausedUntilAppOpens
  case quiet(until: Date)

  public static func current(pause: PauseState, quietUntil: Date?) -> CountersignStatus {
    switch pause {
    case .paused:
      return .paused
    case .pausedUntilAppOpens:
      return .pausedUntilAppOpens
    case .active:
      guard let quietUntil else { return .active }
      return .quiet(until: quietUntil)
    }
  }

  public var icon: CompanionIcon {
    switch self {
    case .active: return .active
    case .paused, .pausedUntilAppOpens: return .paused
    case .quiet: return .quiet
    }
  }

  public func title(timeZone: TimeZone = .current) -> String {
    switch self {
    case .active:
      return "Countersign is on"
    case .paused:
      return "Paused"
    case .pausedUntilAppOpens:
      return "Paused until Countersign opens"
    case .quiet(let until):
      return "Quiet until \(TimeOfDayText.describe(until, timeZone: timeZone))"
    }
  }

  public var detail: String {
    switch self {
    case .active:
      return "Requests from wired hosts show a panel."
    case .paused:
      return "Every request goes to its chat until you resume."
    case .pausedUntilAppOpens:
      return "Every request goes to its chat until you open Countersign or resume."
    case .quiet:
      return "Panels wait until then; each request can still be answered in its chat."
    }
  }

  public var action: CountersignStatusAction {
    switch self {
    case .active: return .pause
    case .paused, .pausedUntilAppOpens: return .resume
    case .quiet: return .endQuietTime
    }
  }
}
