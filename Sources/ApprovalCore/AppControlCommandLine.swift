public struct LaunchAtLoginReply: Sendable, Equatable {
  public var state: LaunchAtLoginState
  public var error: String?

  public init(state: LaunchAtLoginState, error: String? = nil) {
    self.state = state
    self.error = error
  }

  public var encoded: String {
    guard let error else { return state.rawValue }
    return "\(state.rawValue)\n\(error)"
  }

  public init?(encoded: String) {
    let parts = encoded.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    guard let first = parts.first, let state = LaunchAtLoginState(rawValue: String(first)) else {
      return nil
    }
    self.state = state
    self.error = parts.count > 1 ? String(parts[1]) : nil
  }
}

public struct LaunchAtLoginFailure: Error, Sendable, Equatable, CustomStringConvertible {
  public var description: String
}

public enum AppControlCommandLine {
  public static let quitUsage = "usage: countersign quit [--pause]"
  public static let launchAtLoginUsage = "usage: countersign launch-at-login on|off"
  public static let notRunning = "the menu-bar app is not running"
  public static let launchNeedsApp =
    "error: the menu-bar app is not running; open Countersign.app first"
  public static let didNotQuit = "error: the menu-bar app did not quit; quit it from its menu"
  public static let didNotAnswer = "error: the menu-bar app did not answer; try again"

  public static func parseQuit(_ arguments: [String]) -> Bool? {
    switch arguments {
    case []: return false
    case ["--pause"]: return true
    default: return nil
    }
  }

  public static func parseLaunchAtLogin(_ arguments: [String]) -> Bool? {
    switch arguments {
    case ["on"]: return true
    case ["off"]: return false
    default: return nil
    }
  }

  public static func quitMessage(pausing: Bool, alreadyPaused: Bool) -> String {
    if alreadyPaused { return "quit the menu-bar app; panels stay paused" }
    if pausing { return "quit the menu-bar app; panels are paused until it opens again" }
    return "quit the menu-bar app; panels keep appearing"
  }

  public static func launchAtLoginMessage(on: Bool, reply: LaunchAtLoginReply) -> Result<
    String, LaunchAtLoginFailure
  > {
    if let error = reply.error {
      return .failure(LaunchAtLoginFailure(description: "error: \(error)"))
    }
    switch (reply.state, on) {
    case (.requiresApproval, _):
      return .failure(
        LaunchAtLoginFailure(
          description:
            "error: macOS needs your approval first: System Settings, General, Login Items"
        ))
    case (.unavailable, _):
      return .failure(
        LaunchAtLoginFailure(
          description: "error: launch at login is unavailable for this copy of the app"))
    case (.enabled, true):
      return .success("launch at login is on")
    case (.notRegistered, false):
      return .success("launch at login is off")
    default:
      return .failure(LaunchAtLoginFailure(description: "error: launch at login did not change"))
    }
  }
}
