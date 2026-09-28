public enum QuitBehavior: String, Sendable, Equatable, CaseIterable {
  case ask
  case keepShowing
  case pause

  public var title: String {
    switch self {
    case .ask: return "Ask"
    case .keepShowing: return "Keep showing panels"
    case .pause: return "Pause panels"
    }
  }
}

public enum QuitAnswer: Sendable, Equatable {
  case keepShowing
  case pause
  case cancel
}

public struct QuitOutcome: Sendable, Equatable {
  public var pausesPanels: Bool
  public var remembers: QuitBehavior?
  public var keepsExistingPause: Bool

  public init(
    pausesPanels: Bool, remembers: QuitBehavior? = nil, keepsExistingPause: Bool = false
  ) {
    self.pausesPanels = pausesPanels
    self.remembers = remembers
    self.keepsExistingPause = keepsExistingPause
  }
}

public enum QuitDecision: Sendable, Equatable {
  case ask
  case stay
  case quit(QuitOutcome)
}

public enum QuitQuestion {
  public static func decision(for behavior: QuitBehavior, pause: PauseState) -> QuitDecision {
    guard pause == .active else {
      return .quit(QuitOutcome(pausesPanels: false, keepsExistingPause: true))
    }
    switch behavior {
    case .ask: return .ask
    case .keepShowing: return .quit(QuitOutcome(pausesPanels: false))
    case .pause: return .quit(QuitOutcome(pausesPanels: true))
    }
  }

  public static func decision(for answer: QuitAnswer, dontAskAgain: Bool) -> QuitDecision {
    switch answer {
    case .cancel:
      return .stay
    case .keepShowing:
      return .quit(
        QuitOutcome(pausesPanels: false, remembers: dontAskAgain ? .keepShowing : nil))
    case .pause:
      return .quit(QuitOutcome(pausesPanels: true, remembers: dontAskAgain ? .pause : nil))
    }
  }
}
