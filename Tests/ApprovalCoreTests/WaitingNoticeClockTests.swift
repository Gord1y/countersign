import Foundation
import Testing

@testable import ApprovalCore

@Suite struct WaitingNoticeClockTests {
  private let recordedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
  private let delay: TimeInterval = 120

  private func sample(
    after seconds: TimeInterval, isShown: Bool = false, slot: Int? = nil,
    agentAlive: Bool = true, paused: Bool = false, quiet: Bool = false,
    agentAppFrontmost: Bool = false, lastAgentAppFrontmostAfter: TimeInterval? = nil,
    sessionHasLiveTicket: Bool = false, panelOnScreen: Bool = false,
    approvalWaiting: Bool = false, resumed: Bool = false
  ) -> WaitingNoticeSample {
    WaitingNoticeSample(
      now: recordedAt.addingTimeInterval(seconds), recordedAt: recordedAt, delay: delay,
      isShown: isShown, slot: slot, agentAlive: agentAlive, paused: paused, quiet: quiet,
      agentAppFrontmost: agentAppFrontmost,
      lastAgentAppFrontmostAt: lastAgentAppFrontmostAfter.map { recordedAt.addingTimeInterval($0) },
      sessionHasLiveTicket: sessionHasLiveTicket, panelOnScreen: panelOnScreen,
      approvalWaiting: approvalWaiting, resumed: resumed)
  }

  @Test func showsOnceTheDelayHasPassed() {
    #expect(WaitingNoticeClock.decide(sample(after: 119)) == .wait(nil))
    #expect(WaitingNoticeClock.decide(sample(after: 120)) == .show)
  }

  @Test func pauseHoldsIt() {
    #expect(WaitingNoticeClock.decide(sample(after: 300, paused: true)) == .wait(.paused))
  }

  @Test func quietTimeHoldsIt() {
    #expect(WaitingNoticeClock.decide(sample(after: 300, quiet: true)) == .wait(.quiet))
  }

  @Test func beingInTheAgentsAppHoldsIt() {
    let inApp = sample(after: 300, agentAppFrontmost: true, lastAgentAppFrontmostAfter: 300)
    #expect(WaitingNoticeClock.decide(inApp) == .wait(.inAgentApp))
  }

  @Test func aLiveTicketForTheSessionHoldsIt() {
    let ticketOpen = sample(after: 300, sessionHasLiveTicket: true)
    #expect(WaitingNoticeClock.decide(ticketOpen) == .wait(.panelOpen))
  }

  @Test func leavingTheAgentsAppRestartsTheDelay() {
    let justLeft = sample(after: 300, lastAgentAppFrontmostAfter: 250)
    #expect(WaitingNoticeClock.decide(justLeft) == .wait(nil))
    let delayAgain = sample(after: 370, lastAgentAppFrontmostAfter: 250)
    #expect(WaitingNoticeClock.decide(delayAgain) == .show)
  }

  @Test func pauseOrQuietHidesAShownNotice() {
    #expect(
      WaitingNoticeClock.decide(sample(after: 300, isShown: true, paused: true)) == .hide(.paused))
    #expect(
      WaitingNoticeClock.decide(sample(after: 300, isShown: true, quiet: true)) == .hide(.quiet))
    #expect(WaitingNoticeClock.decide(sample(after: 300, isShown: true)) == .wait(nil))
    let shownWithTicket = sample(after: 300, isShown: true, sessionHasLiveTicket: true)
    #expect(WaitingNoticeClock.decide(shownWithTicket) == .wait(nil))
  }

  @Test func aPanelOnScreenHidesAShownNotice() {
    let shown = sample(after: 300, isShown: true, slot: 0, panelOnScreen: true)
    #expect(WaitingNoticeClock.decide(shown) == .hide(.panelOnScreen))
  }

  @Test func aPanelOnScreenHoldsAnUnshownNotice() {
    let unshown = sample(after: 300, panelOnScreen: true)
    #expect(WaitingNoticeClock.decide(unshown) == .wait(.panelOnScreen))
  }

  @Test func pauseStillWinsOverAPanelOnScreen() {
    let unshown = sample(after: 300, paused: true, panelOnScreen: true)
    #expect(WaitingNoticeClock.decide(unshown) == .wait(.paused))
    let shown = sample(after: 300, isShown: true, slot: 0, paused: true, panelOnScreen: true)
    #expect(WaitingNoticeClock.decide(shown) == .hide(.paused))
  }

  @Test func aWaitingApprovalHidesTheNoticeInTheLastSlot() {
    let lastSlot = sample(after: 300, isShown: true, slot: 1, approvalWaiting: true)
    #expect(WaitingNoticeClock.decide(lastSlot) == .hide(.approvalWaiting))
  }

  @Test func aWaitingApprovalLeavesTheNoticeInTheFirstSlot() {
    let firstSlot = sample(after: 300, isShown: true, slot: 0, approvalWaiting: true)
    #expect(WaitingNoticeClock.decide(firstSlot) == .wait(nil))
  }

  @Test func aWaitingApprovalHoldsAnUnshownNotice() {
    let unshown = sample(after: 300, approvalWaiting: true)
    #expect(WaitingNoticeClock.decide(unshown) == .wait(.approvalWaiting))
  }

  @Test func theAgentsAppClosesAShownNotice() {
    let inApp = sample(
      after: 300, isShown: true, paused: true, agentAppFrontmost: true,
      lastAgentAppFrontmostAfter: 300)
    #expect(WaitingNoticeClock.decide(inApp) == .close(.inAgentApp))
  }

  @Test func agentGoneClosesIt() {
    let gone = sample(after: 300, isShown: true, agentAlive: false, resumed: true)
    #expect(WaitingNoticeClock.decide(gone) == .close(.agentExited))
    #expect(WaitingNoticeClock.decide(sample(after: 5, agentAlive: false)) == .close(.agentExited))
  }

  @Test func expiresAfterTwelveHours() {
    let twelveHours = WaitingNoticeClock.maximumAge
    #expect(WaitingNoticeClock.decide(sample(after: twelveHours)) == .show)
    #expect(
      WaitingNoticeClock.decide(sample(after: twelveHours + 1, resumed: true)) == .close(.expired))
  }

  @Test func resumingClosesIt() {
    #expect(WaitingNoticeClock.decide(sample(after: 30, resumed: true)) == .close(.resumed))
    let shown = sample(after: 300, isShown: true, agentAppFrontmost: true, resumed: true)
    #expect(WaitingNoticeClock.decide(shown) == .close(.resumed))
  }
}
