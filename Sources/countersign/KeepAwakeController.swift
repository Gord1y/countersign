import ApprovalCore
import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeController {
  private static let assertionName = "Countersign Keep Mac Awake"

  private let paths: AppPaths
  private let session: KeepAwakeSession
  private let log: EventLog
  private var lastCutoff = Settings.defaultKeepAwakeBatteryCutoff
  private var configProblemIsLogged = false
  private var assertionID: IOPMAssertionID?
  private var sawSession = false
  private var loggedState: KeepAwakeState = .notRunning
  private var assertionFailureIsLogged = false

  init(paths: AppPaths, log: EventLog) {
    self.paths = paths
    session = KeepAwakeSession(paths: paths)
    self.log = log
  }

  var hasSession: Bool {
    session.current() != nil
  }

  func clearAtLaunch() {
    try? session.clear()
  }

  func start(_ duration: KeepAwakeDuration) throws {
    try session.start(duration.end(from: Date()))
  }

  func stop() throws {
    try session.clear()
  }

  func tick() -> KeepAwakeState {
    guard let sessionEnd = session.current() else {
      if assertionID != nil || sawSession {
        try? session.clear()
      }
      return finish(because: nil)
    }
    sawSession = true
    let cutoff: Int
    switch KeepAwakeConfigRead.current(paths: paths) {
    case .usable(let optedIn, let configuredCutoff):
      configProblemIsLogged = false
      guard optedIn else {
        try? session.clear()
        return finish(because: "switched off in Settings")
      }
      lastCutoff = configuredCutoff
      cutoff = configuredCutoff
    case .problem:
      if !configProblemIsLogged {
        log.write("companion: keep awake kept running, config.json has a problem")
        configProblemIsLogged = true
      }
      cutoff = lastCutoff
    }
    let state = KeepAwakePolicy.state(
      optedIn: true, session: sessionEnd, power: KeepAwakePowerSource.current(), cutoff: cutoff)
    if state.holdsIdleSleep {
      holdAssertion()
    } else {
      releaseAssertion()
    }
    logChange(to: state)
    return state
  }

  func endForQuit() {
    try? session.clear()
    _ = finish(because: nil)
  }

  private func finish(because reason: String?) -> KeepAwakeState {
    releaseAssertion()
    sawSession = false
    configProblemIsLogged = false
    if loggedState != .notRunning {
      log.write("companion: keep awake ended" + (reason.map { ", \($0)" } ?? ""))
    }
    loggedState = .notRunning
    return .notRunning
  }

  private func holdAssertion() {
    guard assertionID == nil else { return }
    var created = IOPMAssertionID(0)
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn), Self.assertionName as CFString, &created)
    guard result == kIOReturnSuccess else {
      if !assertionFailureIsLogged {
        log.write("companion: keep awake could not hold idle sleep: \(result)")
        assertionFailureIsLogged = true
      }
      return
    }
    assertionID = created
    assertionFailureIsLogged = false
  }

  private func releaseAssertion() {
    assertionFailureIsLogged = false
    guard let assertionID else { return }
    IOPMAssertionRelease(assertionID)
    self.assertionID = nil
  }

  private func logChange(to state: KeepAwakeState) {
    guard state != loggedState else { return }
    loggedState = state
    switch state {
    case .notRunning:
      break
    case .holding(.at(let date)):
      log.write("companion: keep awake holding until \(TimeOfDayText.describe(date))")
    case .holding(.untilTurnedOff):
      log.write("companion: keep awake holding until turned off")
    case .releasedAtCutoff(_, let cutoff):
      log.write("companion: keep awake released at \(cutoff)% battery")
    }
  }
}
