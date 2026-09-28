import Testing

@testable import ApprovalCore

@Suite struct FirstRunTourTests {
  @Test func hasFourStepsInOrder() {
    #expect(FirstRunTourStep.allCases.map(\.rawValue) == [1, 2, 3, 4])
    #expect(FirstRunTour.stepCount == 4)
  }

  @Test func everyStepHasATitleAndANonEmptyBody() {
    for step in FirstRunTourStep.allCases {
      #expect(!step.title.isEmpty)
      #expect(!step.bodySegments.isEmpty)
      let hasNonEmptyText = step.bodySegments.contains { segment in
        switch segment {
        case .text(let text): return !text.isEmpty
        case .key(let key): return !key.isEmpty
        }
      }
      #expect(hasNonEmptyText)
    }
  }

  @Test func titlesMatchTheApprovedCopy() {
    #expect(FirstRunTourStep.wireAgents.title == "Wire your agents")
    #expect(FirstRunTourStep.howAPanelWaits.title == "How a panel waits")
    #expect(FirstRunTourStep.tryIt.title == "Try it")
    #expect(FirstRunTourStep.makeItYours.title == "Make it yours")
  }

  @Test func onlyHowAPanelWaitsEmbedsTheFourKeycaps() {
    for step in FirstRunTourStep.allCases {
      let keys = step.bodySegments.compactMap { segment in
        if case .key(let key) = segment { return key }
        return nil
      }
      if step == .howAPanelWaits {
        #expect(keys == ["⏎", "esc", "⌫", "⌘⏎"])
      } else {
        #expect(keys.isEmpty)
      }
    }
  }
}
