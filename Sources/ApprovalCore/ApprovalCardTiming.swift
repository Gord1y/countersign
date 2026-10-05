import Foundation

public enum ApprovalCardStage: Sendable, Equatable {
  case notShown
  case shown
  case dismissed

  public var afterQuietTime: ApprovalCardStage {
    self == .dismissed ? .dismissed : .notShown
  }

  public var afterStepAside: ApprovalCardStage {
    self == .dismissed ? .dismissed : .notShown
  }
}

public enum ApprovalCardTiming {
  public static func delay(afterStepAside: Bool, configured: TimeInterval) -> TimeInterval {
    afterStepAside ? 0 : configured
  }

  public static func shouldShow(
    enabled: Bool, mode: PanelRunMode, secondsWaiting: Double, delay: Double, quiet: Bool,
    paused: Bool, stage: ApprovalCardStage
  ) -> Bool {
    guard enabled, mode == .hook, !quiet, !paused, stage == .notShown else { return false }
    return secondsWaiting >= delay
  }
}
