import ApprovalCore
import Foundation

enum StatusCommand {
  static let pauseUsage = "usage: countersign pause"
  static let resumeUsage = "usage: countersign resume"
  static let statusUsage = "usage: countersign status"
  static let snoozeUsage = "usage: countersign snooze <time>|off"
  static let snoozeRangeUsage =
    "usage: countersign snooze <time>|off, where <time> is 10s to 24h, such as 90s, 15m or 1h"

  static func pause(_ arguments: [String]) {
    guard arguments.isEmpty else { CommandLineOutput.fail(pauseUsage) }
    let paths = AppPaths.standard
    let stateSwitches = StateSwitches(
      pauseSwitch: PauseSwitch(file: paths.pauseFile), quietTime: QuietTime(file: paths.quietFile)
    )
    do {
      try stateSwitches.pause()
      print("paused")
    } catch {
      CommandLineOutput.fail("error: \(error)")
    }
  }

  static func resume(_ arguments: [String]) {
    guard arguments.isEmpty else { CommandLineOutput.fail(resumeUsage) }
    let pauseSwitch = PauseSwitch(file: AppPaths.standard.pauseFile)
    do {
      try pauseSwitch.resume()
      print("active")
    } catch {
      CommandLineOutput.fail("error: \(error)")
    }
  }

  static func status(_ arguments: [String]) {
    guard arguments.isEmpty else { CommandLineOutput.fail(statusUsage) }
    let paths = AppPaths.standard
    let pauseSwitch = PauseSwitch(file: paths.pauseFile)
    let queue = TicketQueue(directory: paths.queueDirectory, lockFile: paths.displayLockFile)
    let quietState = QuietState(paths: paths)
    print("state: \(pauseSwitch.state.description)")
    print("queue: \(queue.liveTickets().count) live ticket(s)")
    if let until = quietState.activeUntil() {
      if quietState.windowEnd() == until {
        print("quiet: until \(TimeOfDayText.describe(until)) (quiet hours)")
      } else {
        print("quiet: until \(TimeOfDayText.describe(until))")
      }
    } else {
      print("quiet: off")
    }
    print("log: \(paths.logFile.path)")
  }

  static func snooze(_ arguments: [String]) {
    guard let argument = arguments.first, arguments.count == 1 else {
      CommandLineOutput.fail(snoozeUsage)
    }
    let paths = AppPaths.standard
    let quietTime = QuietTime(file: paths.quietFile)
    if argument == "off" {
      do {
        try QuietState(paths: paths).endNow()
        print("active")
      } catch {
        CommandLineOutput.fail("error: \(error)")
      }
      return
    }
    guard let seconds = DurationText.snoozeSeconds(argument) else {
      CommandLineOutput.fail(snoozeRangeUsage)
    }
    let stateSwitches = StateSwitches(
      pauseSwitch: PauseSwitch(file: paths.pauseFile), quietTime: quietTime)
    do {
      let until = Date().addingTimeInterval(seconds)
      try stateSwitches.snooze(until: until)
      print("quiet until \(TimeOfDayText.describe(until))")
    } catch SnoozeRefusal.paused {
      CommandLineOutput.fail("error: Countersign is paused; run countersign resume first")
    } catch {
      CommandLineOutput.fail("error: \(error)")
    }
  }
}
