import Foundation
import Testing

@testable import ApprovalCore

@Suite struct HandBackPolicyTests {
  @Test func onlyRunModesThatAskThePersonHandBack() {
    #expect(HandBackPolicy.forCursor(.asksEveryTime) == .handsBack)
    #expect(HandBackPolicy.forCursor(.allowlist) == .handsBack)
    #expect(HandBackPolicy.forCursor(.autoReview) == .keepsWaiting)
    #expect(HandBackPolicy.forCursor(.runEverything) == .keepsWaiting)
    #expect(HandBackPolicy.forCursor(.unknown) == .keepsWaiting)
  }

  @Test func aHandBackRunsUnaskedUnlessCursorAsksThePerson() {
    #expect(!CursorRunMode.asksEveryTime.handBackRunsUnasked)
    #expect(!CursorRunMode.allowlist.handBackRunsUnasked)
    #expect(CursorRunMode.autoReview.handBackRunsUnasked)
    #expect(CursorRunMode.runEverything.handBackRunsUnasked)
    #expect(CursorRunMode.unknown.handBackRunsUnasked)
  }

  @Test func onlyAHandBackAnswersInChat() {
    #expect(HandBackPolicy.handsBack.answersInChat)
    #expect(!HandBackPolicy.keepsWaiting.answersInChat)
  }

  @Test func theTimeoutHandsBackOrDenies() {
    #expect(HandBackPolicy.handsBack.timeoutOutcome() == .noDecision)
    #expect(
      HandBackPolicy.keepsWaiting.timeoutOutcome()
        == .deny(
          message: "No answer in Countersign within an hour, so Cursor did not run this.",
          interrupt: false))
    #expect(
      HandBackPolicy.timeoutDenyMessage
        == "No answer in Countersign within an hour, so Cursor did not run this.")
  }

  @Test func logsWhatTheTimeoutDid() {
    #expect(
      HandBackPolicy.handsBack.timeoutLogLine(for: .cursor) == "handed back: cursor timeout near")
    #expect(
      HandBackPolicy.keepsWaiting.timeoutLogLine(for: .cursor) == "denied: cursor timeout near")
  }
}
