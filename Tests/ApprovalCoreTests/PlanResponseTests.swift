import Foundation
import Testing

@testable import ApprovalCore

@Suite struct PlanResponseTests {
  private func loadPlanToolInput() throws -> JSONValue {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-plan"))
    return request.toolInput
  }

  @Test func approveEachMode() throws {
    let toolInput = try loadPlanToolInput()
    for mode in PlanApprovalMode.allCases {
      let outcome = PlanResponse.approve(toolInput: toolInput, mode: mode)
      let expected = ApprovalOutcome.allow(
        updatedInput: toolInput,
        updatedPermissions: [
          .object([
            "type": .string("setMode"),
            "mode": .string(mode.rawValue),
            "destination": .string("session"),
          ])
        ])
      #expect(outcome == expected)
    }
  }

  @Test func keepPlanningWithEmptyFeedbackUsesDefault() {
    let outcome = PlanResponse.keepPlanning(feedback: "   ")
    #expect(outcome == .deny(message: PlanResponse.defaultFeedback, interrupt: false))
  }

  @Test func keepPlanningWithFeedbackTrims() {
    let outcome = PlanResponse.keepPlanning(feedback: "  needs more detail  ")
    #expect(outcome == .deny(message: "needs more detail", interrupt: false))
  }
}
