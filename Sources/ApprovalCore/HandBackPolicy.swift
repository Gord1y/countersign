import Foundation

public enum HandBackPolicy: String, Sendable, Equatable {
  case handsBack
  case keepsWaiting

  public static func forCursor(_ runMode: CursorRunMode) -> HandBackPolicy {
    runMode.handBackRunsUnasked ? .keepsWaiting : .handsBack
  }

  public static let timeoutDenyMessage =
    "No answer in Countersign within an hour, so Cursor did not run this."

  public var answersInChat: Bool {
    self == .handsBack
  }

  public func timeoutOutcome() -> ApprovalOutcome {
    switch self {
    case .handsBack: return .noDecision
    case .keepsWaiting: return .deny(reason: Self.timeoutDenyMessage, interrupt: false)
    }
  }

  public func timeoutLogLine(for host: Host) -> String {
    switch self {
    case .handsBack: return TimeoutHandBack.logLine(for: host)
    case .keepsWaiting: return "denied: \(host.rawValue) timeout near"
    }
  }
}
