import Testing

@testable import ApprovalCore

@Suite struct AppControlCommandLineTests {
  static let states: [LaunchAtLoginState] = [
    .enabled, .notRegistered, .requiresApproval, .unavailable,
  ]

  @Test func parsesQuitArguments() {
    #expect(AppControlCommandLine.parseQuit([]) == false)
    #expect(AppControlCommandLine.parseQuit(["--pause"]) == true)
    #expect(AppControlCommandLine.parseQuit(["now"]) == nil)
    #expect(AppControlCommandLine.parseQuit(["--pause", "x"]) == nil)
  }

  @Test func parsesLaunchAtLoginArguments() {
    #expect(AppControlCommandLine.parseLaunchAtLogin(["on"]) == true)
    #expect(AppControlCommandLine.parseLaunchAtLogin(["off"]) == false)
    #expect(AppControlCommandLine.parseLaunchAtLogin([]) == nil)
    #expect(AppControlCommandLine.parseLaunchAtLogin(["maybe"]) == nil)
    #expect(AppControlCommandLine.parseLaunchAtLogin(["on", "x"]) == nil)
  }

  @Test func repliesRoundTripForEveryState() {
    for state in Self.states {
      let plain = LaunchAtLoginReply(state: state)
      #expect(LaunchAtLoginReply(encoded: plain.encoded) == plain)
      let failed = LaunchAtLoginReply(state: state, error: "Operation not permitted")
      #expect(failed.encoded == "\(state.rawValue)\nOperation not permitted")
      #expect(LaunchAtLoginReply(encoded: failed.encoded) == failed)
    }
  }

  @Test func rejectsRepliesWithoutAKnownState() {
    #expect(LaunchAtLoginReply(encoded: "") == nil)
    #expect(LaunchAtLoginReply(encoded: "sideways\nboom") == nil)
  }

  @Test func wordsTheResults() {
    func message(_ on: Bool, _ state: LaunchAtLoginState, _ error: String? = nil)
      -> Result<String, LaunchAtLoginFailure>
    {
      AppControlCommandLine.launchAtLoginMessage(
        on: on, reply: LaunchAtLoginReply(state: state, error: error))
    }
    #expect(
      message(true, .enabled, "boom") == .failure(LaunchAtLoginFailure(description: "error: boom")))
    #expect(
      message(true, .requiresApproval)
        == .failure(
          LaunchAtLoginFailure(
            description:
              "error: macOS needs your approval first: System Settings, General, Login Items")))
    #expect(
      message(false, .unavailable)
        == .failure(
          LaunchAtLoginFailure(
            description: "error: launch at login is unavailable for this copy of the app")))
    #expect(message(true, .enabled) == .success("launch at login is on"))
    #expect(message(false, .notRegistered) == .success("launch at login is off"))
    #expect(
      message(true, .notRegistered)
        == .failure(LaunchAtLoginFailure(description: "error: launch at login did not change")))
    #expect(
      AppControlCommandLine.quitMessage(pausing: true, alreadyPaused: true)
        == "quit the menu-bar app; panels stay paused")
    #expect(
      AppControlCommandLine.quitMessage(pausing: true, alreadyPaused: false)
        == "quit the menu-bar app; panels are paused until it opens again")
    #expect(
      AppControlCommandLine.quitMessage(pausing: false, alreadyPaused: false)
        == "quit the menu-bar app; panels keep appearing")
  }

  @Test func commandOutcomeKeepsAnExistingPause() {
    #expect(
      QuitQuestion.commandOutcome(pausing: true, pause: .active)
        == QuitOutcome(pausesPanels: true))
    #expect(
      QuitQuestion.commandOutcome(pausing: false, pause: .active)
        == QuitOutcome(pausesPanels: false))
    for pause in [PauseState.paused, .pausedUntilAppOpens] {
      for pausing in [true, false] {
        #expect(
          QuitQuestion.commandOutcome(pausing: pausing, pause: pause)
            == QuitOutcome(pausesPanels: false, keepsExistingPause: true))
      }
    }
  }
}
