import Testing

@testable import ApprovalCore

@Suite struct UpdateCheckRequestsTests {
  @Test func aManualRequestDuringAScheduledCheckIsAnsweredWhenItFinishes() {
    var requests = UpdateCheckRequests()

    let scheduledStarted = requests.begin(manual: false)
    let manualStarted = requests.begin(manual: true)
    let scheduledAnswers = requests.finish(manual: false)

    #expect(scheduledStarted)
    #expect(!manualStarted)
    #expect(scheduledAnswers)
    #expect(!requests.isInFlight)

    let quietStarted = requests.begin(manual: false)
    let quietAnswers = requests.finish(manual: false)

    #expect(quietStarted)
    #expect(!quietAnswers)

    let manualOnlyStarted = requests.begin(manual: true)
    let manualOnlyAnswers = requests.finish(manual: true)

    #expect(manualOnlyStarted)
    #expect(manualOnlyAnswers)
  }
}
