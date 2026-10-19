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

  @Test func codexThresholdsArePercentsOfTheWindow() {
    #expect(
      ContextLadder.codexThresholds(windowTokens: 258_400) == [129_200, 155_040, 180_880, 206_720])
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
    let jump = step(150_000, from: .fresh(now: now))
    #expect(jump.fire == .status)
    #expect(jump.state.fired == [.soft, .status])
    #expect(step(105_000, from: jump.state).fire == nil)
    #expect(step(135_000, from: jump.state).fire == nil)
  }

  @Test func newCompactionIDRearms() {
    let status = step(450_000, from: .fresh(now: now), million: true, compactionID: "a")
    #expect(status.fire == .status)
    let compacted = step(150_000, from: status.state, million: true, compactionID: "b")
    #expect(compacted.fire == nil)
    #expect(compacted.state.fired.isEmpty)
    #expect(compacted.state.peakTokens == 150_000)
    #expect(step(210_000, from: compacted.state, million: true, compactionID: "b").fire == .soft)
  }

  @Test func sharpDropBelowRatioOfPeakRearms() {
    let status = step(400_000, from: .fresh(now: now), million: true)
    #expect(status.fire == .status)
    let dropped = step(230_000, from: status.state, million: true)
    #expect(dropped.fire == .soft)
    #expect(dropped.state.fired == [.soft])
    #expect(dropped.state.peakTokens == 230_000)
  }

  @Test func mildDropKeepsFiredLevels() {
    let status = step(400_000, from: .fresh(now: now), million: true)
    let dipped = step(300_000, from: status.state, million: true)
    #expect(dipped.fire == nil)
    #expect(dipped.state.fired == [.soft, .status])
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

  @Test func fourRungLadderFiresStopAtTheFourthThreshold() {
    var settings = ContextLadderSettings.default
    settings.standardThresholds = [100_000, 120_000, 140_000, 160_000]
    let insist = step(150_000, from: .fresh(now: now), settings: settings)
    #expect(insist.fire == .insist)
    let stop = step(160_000, from: insist.state, settings: settings)
    #expect(stop.fire == .stop)
    #expect(stop.state.fired == [.soft, .status, .insist, .stop])
  }

  @Test func threeRungLadderFiresStopAtTheThirdThreshold() {
    var settings = ContextLadderSettings.default
    settings.standardThresholds = [100, 200, 300]
    #expect(step(300, from: .fresh(now: now), settings: settings).fire == .stop)
    #expect(step(250, from: .fresh(now: now), settings: settings).fire == .status)
  }

  @Test func twoRungLadderNeverFiresStop() {
    var settings = ContextLadderSettings.default
    settings.standardThresholds = [100, 200]
    #expect(step(10_000, from: .fresh(now: now), settings: settings).fire == .status)
  }

  @Test func levelsForRungCount() {
    #expect(ContextLevel.levels(forRungCount: 2) == [.soft, .status])
    #expect(ContextLevel.levels(forRungCount: 3) == [.soft, .status, .stop])
    #expect(ContextLevel.levels(forRungCount: 4) == ContextLevel.allCases)
    #expect(ContextLevel.levels(forRungCount: 1) == [.soft])
    #expect(ContextLevel.levels(forRungCount: 0).isEmpty)
  }

  @Test func jumpPastTheStopRungFiresStopOnly() {
    let jump = step(170_000, from: .fresh(now: now))
    #expect(jump.fire == .stop)
    #expect(jump.state.fired == [.soft, .status, .insist, .stop])
  }

  @Test func limitedToStopFiresNothingBelowIt() {
    let previous = ContextCheckpointState.fresh(now: now)
    let result = ContextLadder.step(
      tokens: 150_000, modelID: nil, hasMillionTokenWindow: false, compactionID: nil,
      previous: previous, settings: .default, levels: [.stop])
    #expect(result.fire == nil)
    #expect(result.state.fired == previous.fired)
  }

  @Test func limitedToStopFiresStopPastIt() {
    let result = ContextLadder.step(
      tokens: 170_000, modelID: nil, hasMillionTokenWindow: false, compactionID: nil,
      previous: .fresh(now: now), settings: .default, levels: [.stop])
    #expect(result.fire == .stop)
    #expect(result.state.fired == [.soft, .status, .insist, .stop])
  }

  @Test func levelsOrderAscending() {
    #expect(ContextLevel.insist < ContextLevel.stop)
    #expect(ContextLevel.soft < ContextLevel.status)
    #expect(ContextLevel.status < ContextLevel.insist)
  }
}
