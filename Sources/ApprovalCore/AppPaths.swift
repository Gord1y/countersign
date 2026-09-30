import Foundation

public struct AppPaths: Sendable, Equatable {
  public var home: URL
  public var xdgConfigHome: String?
  public var claudeConfigDir: String?

  public init(home: URL, xdgConfigHome: String? = nil, claudeConfigDir: String? = nil) {
    self.home = home
    self.xdgConfigHome = xdgConfigHome
    self.claudeConfigDir = claudeConfigDir
  }

  public static var standard: AppPaths {
    let environment = ProcessInfo.processInfo.environment
    return AppPaths(
      home: FileManager.default.homeDirectoryForCurrentUser,
      xdgConfigHome: environment["XDG_CONFIG_HOME"],
      claudeConfigDir: environment["CLAUDE_CONFIG_DIR"])
  }

  public var supportDirectory: URL {
    home
      .appendingPathComponent("Library")
      .appendingPathComponent("Application Support")
      .appendingPathComponent("Countersign")
  }

  public var logsDirectory: URL {
    home
      .appendingPathComponent("Library")
      .appendingPathComponent("Logs")
      .appendingPathComponent("Countersign")
  }

  public var claudeSessionsDirectory: URL {
    if let claudeConfigDir, !claudeConfigDir.isEmpty {
      return URL(fileURLWithPath: claudeConfigDir).appendingPathComponent("sessions")
    }
    return
      home
      .appendingPathComponent(".claude")
      .appendingPathComponent("sessions")
  }

  public var queueDirectory: URL {
    supportDirectory.appendingPathComponent("queue")
  }

  public var contextCheckpointsDirectory: URL {
    supportDirectory.appendingPathComponent("context")
  }

  public var waitingDirectory: URL {
    supportDirectory.appendingPathComponent("waiting")
  }

  public var displayLockFile: URL {
    queueDirectory.appendingPathComponent("display.lock")
  }

  public var pauseFile: URL {
    supportDirectory.appendingPathComponent("paused")
  }

  public var quietFile: URL {
    supportDirectory.appendingPathComponent("quiet-until")
  }

  public var quietHoursSkippedFile: URL {
    supportDirectory.appendingPathComponent("quiet-hours-skipped-until")
  }

  public var codexHookTrustFile: URL {
    supportDirectory.appendingPathComponent("codex-hook-trust.json")
  }

  public var codexWaitingHookTrustFile: URL {
    supportDirectory.appendingPathComponent("codex-waiting-hook-trust.json")
  }

  public var tourShownFile: URL {
    supportDirectory.appendingPathComponent("tour-shown")
  }

  public var companionLockFile: URL {
    supportDirectory.appendingPathComponent("companion.lock")
  }

  public var updateCheckFile: URL {
    supportDirectory.appendingPathComponent("update-check.json")
  }

  public var decisionHistoryFile: URL {
    supportDirectory.appendingPathComponent("history.jsonl")
  }

  public var decisionHistoryLockFile: URL {
    supportDirectory.appendingPathComponent("history.lock")
  }

  public var logFile: URL {
    logsDirectory.appendingPathComponent("countersign.log")
  }

  public var configDirectory: URL {
    if let xdgConfigHome, !xdgConfigHome.isEmpty {
      return URL(fileURLWithPath: xdgConfigHome).appendingPathComponent("countersign")
    }
    return
      home
      .appendingPathComponent(".config")
      .appendingPathComponent("countersign")
  }

  public var configFile: URL {
    configDirectory.appendingPathComponent("config.json")
  }
}
