import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointPlannerTests {
  private let now = Date(timeIntervalSince1970: 1_000)

  private func reading(_ tokens: Int) -> ContextReading {
    ContextReading(
      tokens: tokens, modelID: "claude-opus-5-5", hasMillionTokenWindow: false, compactionID: nil)
  }

  private func settings(mode: ContextCheckpointMode) -> ContextCheckpointSettings {
    var settings = ContextCheckpointSettings.default
    settings.enabled = true
    settings.mode = mode
    return settings
  }

  @Test func silentModeInjectsTheRenderedNoteOfTheCrossedLevel() {
    let settings = settings(mode: .silent)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(101_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: "/t.jsonl", project: "shop-api", now: now)

    let expected = ContextCheckpointNotes.render(
      settings.notes.soft, tokens: 101_000, handoffFile: settings.handoffFile)
    #expect(plan.decision == .inject(expected))
    #expect(plan.state.fired == [.soft])
  }

  @Test func panelModeAsksWithTheLevelAndTheLadderUsed() {
    let settings = settings(mode: .panel)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(165_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: nil, project: "shop-api", now: now)

    let expected = ContextCheckpointPrompt(
      tokens: 165_000, level: .insist, ladder: [100_000, 130_000, 160_000],
      modelID: "claude-opus-5-5", handoffFile: settings.handoffFile, notes: settings.notes)
    #expect(plan.decision == .panel(expected))
  }

  @Test func noCrossingKeepsTheStateCurrent() {
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(50_000), previous: .fresh(now: Date(timeIntervalSince1970: 0)),
      settings: settings(mode: .panel), transcriptPath: "/t.jsonl", project: "shop-api",
      now: now)

    #expect(plan.decision == .nothing)
    #expect(plan.state.lastTokens == 50_000)
    #expect(plan.state.project == "shop-api")
    #expect(plan.state.transcriptPath == "/t.jsonl")
    #expect(plan.state.updatedAt == now)
  }
}
