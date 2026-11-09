import ApprovalCore
import Foundation

enum KeepAwakeCommand {
  static let usage = KeepAwakeCommandText.usage
  static let durationRange: ClosedRange<TimeInterval> = 60...86400

  static func run(_ arguments: [String]) {
    switch arguments.first {
    case "on": turnOn(Array(arguments.dropFirst()))
    case "off": turnOff(Array(arguments.dropFirst()))
    case "status": showStatus(Array(arguments.dropFirst()))
    default: CommandLineOutput.fail(usage)
    }
  }

  static func statusLine(paths: AppPaths) -> String {
    let session = KeepAwakeSession(paths: paths).current()
    let optedIn: Bool
    let cutoff: Int
    switch KeepAwakeConfigRead.current(paths: paths) {
    case .usable(let configuredOptIn, let configuredCutoff):
      optedIn = configuredOptIn
      cutoff = configuredCutoff
    case .problem:
      optedIn = session != nil
      cutoff = Settings.defaultKeepAwakeBatteryCutoff
    }
    let state = KeepAwakePolicy.state(
      optedIn: optedIn, session: session, power: KeepAwakePowerSource.current(), cutoff: cutoff)
    return KeepAwakeCommandText.statusLine(
      optedIn: optedIn, appRunning: CompanionProbe.isRunning(paths: paths), state: state)
  }

  private static func turnOn(_ arguments: [String]) {
    let paths = AppPaths.standard
    let file = ConfigFileLoader.load(paths: paths).file
    let duration = file.keepAwakeDuration ?? Settings.defaultKeepAwakeDuration
    let end: KeepAwakeEnd
    switch arguments.count {
    case 0:
      end = duration.end(from: Date())
    case 1 where arguments[0] == "--forever":
      end = .untilTurnedOff
    case 2 where arguments[0] == "--for":
      guard let seconds = DurationText.parse(arguments[1]), durationRange.contains(seconds) else {
        CommandLineOutput.fail(KeepAwakeCommandText.timeUsage)
      }
      end = .at(Date().addingTimeInterval(seconds))
    default:
      CommandLineOutput.fail(usage)
    }
    guard case .usable(let optedIn, _) = KeepAwakeConfigRead.current(paths: paths) else {
      CommandLineOutput.fail(KeepAwakeCommandText.configProblem)
    }
    guard optedIn else {
      CommandLineOutput.fail(KeepAwakeCommandText.notOptedIn)
    }
    guard CompanionProbe.isRunning(paths: paths) else {
      CommandLineOutput.fail(KeepAwakeCommandText.appNotRunning)
    }
    do {
      try KeepAwakeSession(paths: paths).start(end)
      print(KeepAwakeCommandText.started(end))
    } catch {
      CommandLineOutput.fail("error: \(error)")
    }
  }

  private static func turnOff(_ arguments: [String]) {
    guard arguments.isEmpty else { CommandLineOutput.fail(usage) }
    let session = KeepAwakeSession(paths: AppPaths.standard)
    let hadSession = session.current() != nil
    do {
      try session.clear()
      print(hadSession ? KeepAwakeCommandText.stopped : KeepAwakeCommandText.notRunning)
    } catch {
      CommandLineOutput.fail("error: \(error)")
    }
  }

  private static func showStatus(_ arguments: [String]) {
    guard arguments.isEmpty else { CommandLineOutput.fail(usage) }
    print(statusLine(paths: AppPaths.standard))
  }
}
