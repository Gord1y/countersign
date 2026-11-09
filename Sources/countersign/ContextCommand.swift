import ApprovalCore
import Foundation

enum ContextCommand {
  static let usage = ContextCommandText.usage

  static func run(_ arguments: [String]) {
    guard arguments.isEmpty else { CommandLineOutput.fail(usage) }
    let paths = AppPaths.standard
    let configFile = ConfigFileLoader.load(paths: paths, soundNames: SystemSounds.installedNames)
      .file
    let settings = Settings.resolve(file: configFile, host: .claude).contextCheckpoints
    guard settings.enabled else {
      print(ContextCommandText.checkpointsOff)
      return
    }
    let rows = ContextMeter.rows(
      store: ContextCheckpointStore(directory: paths.contextCheckpointsDirectory),
      isLive: {
        ContextMeter.isLive(sessionID: $0, sessionsDirectory: paths.claudeSessionsDirectory)
      },
      settings: settings)
    if rows.isEmpty {
      print(ContextCommandText.noSessions)
    } else {
      for row in rows {
        print(row.title)
      }
    }
  }
}
