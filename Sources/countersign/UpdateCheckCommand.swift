import ApprovalCore
import Foundation

enum RunningExecutable {
  static func runningStablePath() -> String {
    guard let resolved = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
      return "(unresolved)"
    }
    return StableExecutablePath.stable(
      forResolved: resolved, home: FileManager.default.homeDirectoryForCurrentUser,
      isExecutable: FileManager.default.isExecutableFile(atPath:))
  }
}

enum UpdateCheckCommand {
  static let usage = UpdateCheckCommandText.usage

  @MainActor
  static func run(_ arguments: [String]) -> Never {
    guard arguments.isEmpty else { CommandLineOutput.fail(usage) }
    Task { @MainActor in
      let outcome = await UpdateFetcher.fetch(currentVersion: CountersignVersion.current)
      record(outcome)
      var availability: UpdateAvailability?
      if case .newerAvailable(let version) = outcome {
        availability = UpdateAvailability(
          version: version,
          upgradeCommand: UpdateCommand.upgrade(
            forStablePath: RunningExecutable.runningStablePath()),
          releaseNotesURL: UpdateCommand.releaseNotesURL(version: version))
      }
      let lines = UpdateCheckCommandText.lines(
        outcome: outcome, currentVersion: CountersignVersion.current, availability: availability)
      for line in lines {
        print(line)
      }
      exit(UpdateCheckCommandText.succeeded(outcome) ? 0 : 1)
    }
    dispatchMain()
  }

  private static func record(_ outcome: UpdateCheckOutcome) {
    let file = AppPaths.standard.updateCheckFile
    let previous = UpdateCheckStateStore.load(file: file)?
      .reevaluated(currentVersion: CountersignVersion.current)
    guard let state = UpdateCheckState.recording(outcome, at: Date(), over: previous),
      state != previous
    else { return }
    do {
      try UpdateCheckStateStore.save(state, to: file)
    } catch {
      CommandLineOutput.writeError("could not save update-check.json: \(error)")
    }
  }
}
