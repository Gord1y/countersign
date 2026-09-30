import Foundation

public enum WaitingNoticeHold: String, Sendable, Equatable {
  case paused
  case quiet
  case inAgentApp = "in the agent's app"
  case panelOpen = "panel open"
}

public enum WaitingNoticeClose: String, Sendable, Equatable {
  case resumed
  case goThere = "go there"
  case dismissed
  case agentExited = "agent exited"
  case expired
  case inAgentApp = "in the agent's app"
}

public enum WaitingNoticeStep: Sendable, Equatable {
  case wait(WaitingNoticeHold?)
  case show
  case hide(WaitingNoticeHold)
  case close(WaitingNoticeClose)
}

public struct WaitingNoticeSample: Sendable, Equatable {
  public var now: Date
  public var recordedAt: Date
  public var delay: TimeInterval
  public var isShown: Bool
  public var agentAlive: Bool
  public var paused: Bool
  public var quiet: Bool
  public var agentAppFrontmost: Bool
  public var lastAgentAppFrontmostAt: Date?
  public var sessionHasLiveTicket: Bool
  public var resumed: Bool

  public init(
    now: Date, recordedAt: Date, delay: TimeInterval, isShown: Bool, agentAlive: Bool,
    paused: Bool, quiet: Bool, agentAppFrontmost: Bool, lastAgentAppFrontmostAt: Date?,
    sessionHasLiveTicket: Bool, resumed: Bool
  ) {
    self.now = now
    self.recordedAt = recordedAt
    self.delay = delay
    self.isShown = isShown
    self.agentAlive = agentAlive
    self.paused = paused
    self.quiet = quiet
    self.agentAppFrontmost = agentAppFrontmost
    self.lastAgentAppFrontmostAt = lastAgentAppFrontmostAt
    self.sessionHasLiveTicket = sessionHasLiveTicket
    self.resumed = resumed
  }
}

public enum WaitingNoticeClock {
  public static let maximumAge: TimeInterval = 12 * 60 * 60

  public static func decide(_ sample: WaitingNoticeSample) -> WaitingNoticeStep {
    guard sample.agentAlive else { return .close(.agentExited) }
    guard sample.now.timeIntervalSince(sample.recordedAt) <= maximumAge else {
      return .close(.expired)
    }
    guard !sample.resumed else { return .close(.resumed) }
    if sample.isShown {
      if sample.agentAppFrontmost {
        return .close(.inAgentApp)
      }
      if sample.paused {
        return .hide(.paused)
      }
      if sample.quiet {
        return .hide(.quiet)
      }
      return .wait(nil)
    }
    if let hold = hold(sample) {
      return .wait(hold)
    }
    guard sample.now >= dueAt(sample) else { return .wait(nil) }
    return .show
  }

  private static func hold(_ sample: WaitingNoticeSample) -> WaitingNoticeHold? {
    if sample.paused {
      return .paused
    }
    if sample.quiet {
      return .quiet
    }
    if sample.agentAppFrontmost {
      return .inAgentApp
    }
    if sample.sessionHasLiveTicket {
      return .panelOpen
    }
    return nil
  }

  private static func dueAt(_ sample: WaitingNoticeSample) -> Date {
    let start = max(sample.recordedAt, sample.lastAgentAppFrontmostAt ?? sample.recordedAt)
    return start.addingTimeInterval(sample.delay)
  }
}
