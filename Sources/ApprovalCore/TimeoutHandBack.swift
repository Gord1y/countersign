import Foundation

public enum TimeoutHandBack {
  public static let entryTimeoutSeconds = HookSetup.timeoutSeconds
  public static let marginSeconds = 60

  public static func deadline(for host: Host) -> Duration? {
    switch host {
    case .claude, .codex: return nil
    case .cursor, .antigravity: return .seconds(entryTimeoutSeconds - marginSeconds)
    }
  }

  public static func isDue(host: Host, elapsed: Duration) -> Bool {
    guard let deadline = deadline(for: host) else { return false }
    return elapsed >= deadline
  }

  public static func logLine(for host: Host) -> String {
    "handed back: \(host.rawValue) timeout near"
  }
}
