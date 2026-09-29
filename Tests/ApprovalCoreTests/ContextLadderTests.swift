import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextLadderTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func step(
    _ tokens: Int, from previous: ContextCheckpointState, million: Bool = false,
    compactionID: String? = nil, modelID: String? = nil,
    settings: ContextLadderSettings = .default
  ) -> ContextLadderStep {
    ContextLadder.step(
      tokens: tokens, modelID: modelID, hasMillionTokenWindow: million,
      compactionID: compactionID, previous: previous, settings: settings)
  }

  @Test func picksThresholdsByModelAndWindow() {
    var settings = ContextLadderSettings.default
    settings.modelThresholds = [
      "claude-opus": [1, 2, 3], "claude-opus-5-5[1m]": [4, 5, 6],
    ]
    #expect(
      ContextLadder.thresholds(modelID: nil, hasMillionTokenWindow: false, settings: settings)
        == ContextCheckpointSettings.defaultStandardThresholds)
    #expect(
      ContextLadder.thresholds(modelID: nil, hasMillionTokenWindow: true, settings: settings)
        == ContextCheckpointSettings.defaultMillionThresholds)
    #expect(
      ContextLadder.thresholds(
        modelID: "claude-opus-5-5[1m]", hasMillionTokenWindow: true, settings: settings)
        == [4, 5, 6])
    #expect(
      ContextLadder.thresholds(
        modelID: "claude-opus-5", hasMillionTokenWindow: false, settings: settings)
        == [1, 2, 3])
  }

  @Test func staysQuietBelowTheFirstThreshold() {
    let result = step(99_999, from: .fresh(now: now))
    #expect(result.fire == nil)
    #expect(result.state.lastTokens == 99_999)
    #expect(result.state.peakTokens == 99_999)
  }

  @Test func firesSoftOnceOnly() {
    let first = step(100_000, from: .fresh(now: now))
    #expect(first.fire == .soft)
    #expect(first.state.fired == [.soft])
    #expect(step(100_000, from: first.state).fire == nil)
  }

  @Test func firesStatusAfterSoft() {
    let soft = step(100_000, from: .fresh(now: now))
    let status = step(130_000, from: soft.state)
    #expect(status.fire == .status)
    #expect(status.state.fired == [.soft, .status])
  }

  @Test func jumpFiresOnlyTheHighestAndLowerOnesCountAsFired() {
    let jump = step(170_000, from: .fresh(now: now))
    #expect(jump.fire == .insist)
    #expect(jump.state.fired == [.soft, .status, .insist])
    #expect(step(105_000, from: jump.state).fire == nil)
    #expect(step(135_000, from: jump.state).fire == nil)
  }

  @Test func newCompactionIDRearms() {
    let insist = step(450_000, from: .fresh(now: now), million: true, compactionID: "a")
    #expect(insist.fire == .insist)
    let compacted = step(150_000, from: insist.state, million: true, compactionID: "b")
    #expect(compacted.fire == nil)
    #expect(compacted.state.fired.isEmpty)
    #expect(compacted.state.peakTokens == 150_000)
    #expect(step(210_000, from: compacted.state, million: true, compactionID: "b").fire == .soft)
  }

  @Test func sharpDropBelowRatioOfPeakRearms() {
    let insist = step(400_000, from: .fresh(now: now), million: true)
    #expect(insist.fire == .insist)
    let dropped = step(230_000, from: insist.state, million: true)
    #expect(dropped.fire == .soft)
    #expect(dropped.state.fired == [.soft])
    #expect(dropped.state.peakTokens == 230_000)
  }

  @Test func mildDropKeepsFiredLevels() {
    let insist = step(400_000, from: .fresh(now: now), million: true)
    let dipped = step(300_000, from: insist.state, million: true)
    #expect(dipped.fire == nil)
    #expect(dipped.state.fired == [.soft, .status, .insist])
  }

  @Test func mutedSessionNeverFires() {
    var muted = ContextCheckpointState.fresh(now: now)
    muted.muted = true
    let crossed = step(170_000, from: muted)
    #expect(crossed.fire == nil)
    #expect(crossed.state.fired.isEmpty)
    let rearmed = step(120_000, from: crossed.state, compactionID: "new")
    #expect(rearmed.fire == nil)
    #expect(rearmed.state.muted)
  }

  @Test func keepsPreviousModelAndCompactionWhenReadingHasNone() {
    var previous = ContextCheckpointState.fresh(now: now)
    previous.modelID = "claude-opus-5"
    previous.compactionID = "a"
    let result = step(10, from: previous)
    #expect(result.state.modelID == "claude-opus-5")
    #expect(result.state.compactionID == "a")
  }

  @Test func levelsOrderAscending() {
    #expect(ContextLevel.soft < ContextLevel.status)
    #expect(ContextLevel.status < ContextLevel.insist)
  }
}
