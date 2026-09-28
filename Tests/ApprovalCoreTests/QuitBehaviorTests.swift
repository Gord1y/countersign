import Testing

@testable import ApprovalCore

@Suite struct QuitBehaviorTests {
  @Test func readsAndWritesTheConfigSpelling() {
    #expect(QuitBehavior.allCases.map(\.rawValue) == ["ask", "keepShowing", "pause"])
    #expect(QuitBehavior(rawValue: "keepShowing") == .keepShowing)
    #expect(QuitBehavior(rawValue: "Pause") == nil)
  }

  @Test func titlesEachChoiceForSettings() {
    #expect(QuitBehavior.allCases.map(\.title) == ["Ask", "Keep showing panels", "Pause panels"])
  }

  @Test func asksOnlyWhenNothingIsRemembered() {
    #expect(QuitQuestion.decision(for: .ask, pause: .active) == .ask)
  }

  @Test func aRememberedChoiceQuitsAtOnceWithoutWritingItAgain() {
    #expect(
      QuitQuestion.decision(for: .keepShowing, pause: .active)
        == .quit(QuitOutcome(pausesPanels: false)))
    #expect(
      QuitQuestion.decision(for: .pause, pause: .active)
        == .quit(QuitOutcome(pausesPanels: true)))
  }

  @Test(arguments: QuitBehavior.allCases)
  func quitsWithoutAskingAndKeepsAPauseAlreadyOn(behavior: QuitBehavior) {
    let keepsThePause = QuitDecision.quit(
      QuitOutcome(pausesPanels: false, remembers: nil, keepsExistingPause: true))
    #expect(QuitQuestion.decision(for: behavior, pause: .paused) == keepsThePause)
    #expect(QuitQuestion.decision(for: behavior, pause: .pausedUntilAppOpens) == keepsThePause)
  }

  @Test func keepShowingQuitsWithoutPausing() {
    #expect(
      QuitQuestion.decision(for: .keepShowing, dontAskAgain: false)
        == .quit(QuitOutcome(pausesPanels: false, remembers: nil)))
    #expect(
      QuitQuestion.decision(for: .keepShowing, dontAskAgain: true)
        == .quit(QuitOutcome(pausesPanels: false, remembers: .keepShowing)))
  }

  @Test func pauseQuitsAndPauses() {
    #expect(
      QuitQuestion.decision(for: .pause, dontAskAgain: false)
        == .quit(QuitOutcome(pausesPanels: true, remembers: nil)))
    #expect(
      QuitQuestion.decision(for: .pause, dontAskAgain: true)
        == .quit(QuitOutcome(pausesPanels: true, remembers: .pause)))
  }

  @Test func cancelStaysAndIgnoresDontAskAgain() {
    #expect(QuitQuestion.decision(for: .cancel, dontAskAgain: false) == .stay)
    #expect(QuitQuestion.decision(for: .cancel, dontAskAgain: true) == .stay)
  }
}
