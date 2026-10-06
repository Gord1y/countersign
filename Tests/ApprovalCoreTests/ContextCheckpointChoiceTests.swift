import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointChoiceTests {
  private let prompt = ContextCheckpointPrompt(
    tokens: 131_000, level: .status, ladder: [100_000, 130_000, 160_000], modelID: nil,
    handoffFile: "notes/handoff.md",
    notes: ContextCheckpointNotes(
      soft: "s", status: "t", insist: "i", compact: "compact {tokens} {handoffFile}",
      handoff: "handoff {tokens} {handoffFile}"))

  @Test func titles() {
    #expect(ContextCheckpointChoice.continueWorking.title == "Continue")
    #expect(ContextCheckpointChoice.compactAfterStep.title == "Compact after this step")
    #expect(ContextCheckpointChoice.handOff.title == "Hand off & start fresh")
    #expect(ContextCheckpointChoice.notThisSession.title == "Not this session")
  }

  @Test func compactAndHandOffRenderTheirNotes() {
    #expect(
      ContextCheckpointChoice.compactAfterStep.outcome(for: prompt)
        == .addContext("compact 131K notes/handoff.md"))
    #expect(
      ContextCheckpointChoice.handOff.outcome(for: prompt)
        == .addContext("handoff 131K notes/handoff.md"))
  }

  @Test func continueAndNotThisSessionAddNothing() {
    #expect(ContextCheckpointChoice.continueWorking.outcome(for: prompt) == .noDecision)
    #expect(ContextCheckpointChoice.notThisSession.outcome(for: prompt) == .noDecision)
  }

  @Test func highlightsByLevel() {
    #expect(ContextCheckpointChoice.highlighted(for: .soft) == .compactAfterStep)
    #expect(ContextCheckpointChoice.highlighted(for: .status) == .compactAfterStep)
    #expect(ContextCheckpointChoice.highlighted(for: .insist) == .handOff)
  }
}
