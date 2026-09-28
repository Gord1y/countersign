import Testing

@testable import ApprovalCore

@Suite struct TestPanelAdmissionTests {
  @Test func anEmptyQueueShowsTheTestPanel() {
    #expect(TestPanelAdmission.decide(panelOnScreen: false, otherTickets: 0) == .show)
  }

  @Test(arguments: [1, 2, 11])
  func aRequestInTheQueueRefusesTheTestPanel(_ otherTickets: Int) {
    #expect(
      TestPanelAdmission.decide(panelOnScreen: false, otherTickets: otherTickets)
        == .refuse(.requestWaiting))
  }

  @Test(arguments: [0, 1, 3])
  func aPanelOnScreenRefusesTheTestPanelWhateverElseWaits(_ otherTickets: Int) {
    #expect(
      TestPanelAdmission.decide(panelOnScreen: true, otherTickets: otherTickets)
        == .refuse(.panelOnScreen))
  }

  @Test func eachRefusalSaysWhatToAnswerFirst() {
    #expect(TestPanelRefusal.allCases == [.panelOnScreen, .requestWaiting])
    #expect(
      TestPanelRefusal.panelOnScreen.message == "a panel is already on screen; answer it first")
    #expect(
      TestPanelRefusal.requestWaiting.message
        == "a request is waiting for a panel; answer it first")
  }
}
