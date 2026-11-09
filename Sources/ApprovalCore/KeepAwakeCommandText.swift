import Foundation

public enum KeepAwakeCommandText {
  public static let usage =
    "usage: countersign keep-awake on [--for <time>|--forever] | off | status"
  public static let timeUsage =
    "usage: countersign keep-awake on --for <time>, where <time> is 1m to 24h, such as 90m or 4h"
  public static let notOptedIn =
    "error: Keep Mac Awake is off; turn it on first in Countersign.app, Settings, App"
  public static let appNotRunning =
    "error: the menu-bar app keeps this Mac awake and it is not running; open Countersign.app first"
  public static let stopped = "stopped"
  public static let notRunning = "not running"

  private static let displayNote = "the display still turns off and locks"

  public static func started(_ end: KeepAwakeEnd, timeZone: TimeZone = .current) -> String {
    switch end {
    case .at(let date):
      return
        "keeping this Mac awake until \(TimeOfDayText.describe(date, timeZone: timeZone));"
        + " \(displayNote)"
    case .untilTurnedOff:
      return "keeping this Mac awake until you turn it off; \(displayNote)"
    }
  }

  public static func statusLine(
    optedIn: Bool, appRunning: Bool, state: KeepAwakeState, timeZone: TimeZone = .current
  ) -> String {
    guard optedIn else { return "off" }
    guard appRunning else { return "not running (the menu-bar app is closed)" }
    switch state {
    case .notRunning:
      return notRunning
    case .holding(.at(let date)):
      return "holding until \(TimeOfDayText.describe(date, timeZone: timeZone))"
    case .holding(.untilTurnedOff):
      return "holding until turned off"
    case .releasedAtCutoff(.at(let date), let cutoff):
      return
        "released at \(cutoff)% battery; holds again if plugged in,"
        + " until \(TimeOfDayText.describe(date, timeZone: timeZone))"
    case .releasedAtCutoff(.untilTurnedOff, let cutoff):
      return "released at \(cutoff)% battery; holds again if plugged in"
    }
  }
}
