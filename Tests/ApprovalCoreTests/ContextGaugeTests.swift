import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextGaugeTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func reading(
    _ tokens: Int, million: Bool = false, modelID: String? = nil, lastActivity: Date? = nil,
    cacheLifetime: ContextCacheLifetime? = nil
  ) -> ContextReading {
    ContextReading(
      tokens: tokens, modelID: modelID, hasMillionTokenWindow: million, compactionID: nil,
      lastActivity: lastActivity, cacheLifetime: cacheLifetime)
  }

  private func state(tokens: Int = 0, modelID: String? = nil) -> ContextCheckpointState {
    var state = ContextCheckpointState.fresh(now: now)
    state.lastTokens = tokens
    state.modelID = modelID
    return state
  }

  private func gauge(
    reading: ContextReading?, state: ContextCheckpointState? = nil,
    settings: ContextCheckpointSettings = .default
  ) -> ContextGauge? {
    ContextGauge.make(reading: reading, state: state, settings: settings, now: now)
  }

  @Test func readingWithMillionWindowGivesMillion() {
    let result = gauge(reading: reading(150_000, million: true))
    #expect(result?.windowTokens == 1_000_000)
    #expect(result?.windowPercent == 15)
  }

  @Test func stateModelWithMillionMarkerGivesMillion() {
    let result = gauge(reading: reading(150_000), state: state(modelID: "claude-opus-4-7[1m]"))
    #expect(result?.windowTokens == 1_000_000)
  }

  @Test func tokensAboveStandardWindowGiveMillion() {
    let result = gauge(reading: reading(200_001))
    #expect(result?.windowTokens == 1_000_000)
  }

  @Test func standardWindowOtherwise() {
    let result = gauge(reading: reading(150_000))
    #expect(result?.windowTokens == 200_000)
    #expect(result?.windowPercent == 75)
  }

  @Test func percentRounds() {
    #expect(gauge(reading: reading(100_900))?.windowPercent == 50)
    #expect(gauge(reading: reading(101_100))?.windowPercent == 51)
  }

  @Test func passedRungsOnAFourRungLadder() {
    let result = gauge(reading: reading(125_000))
    #expect(result?.ladder == [100_000, 120_000, 140_000, 160_000])
    #expect(result?.passed == [.soft, .status])
  }

  @Test func passedRungsOnAThreeRungLadder() {
    var settings = ContextCheckpointSettings.default
    settings.standardThresholds = [50_000, 80_000, 110_000]
    let result = gauge(reading: reading(90_000), settings: settings)
    #expect(result?.ladder == [50_000, 80_000, 110_000])
    #expect(result?.passed == [.soft, .status])
  }

  @Test func rungAtTheTokenCountIsPassed() {
    #expect(gauge(reading: reading(100_000))?.passed == [.soft])
    #expect(gauge(reading: reading(99_999))?.passed == [])
  }

  @Test func modelThresholdsWin() {
    var settings = ContextCheckpointSettings.default
    settings.modelThresholds = ["claude-opus": [10_000, 20_000, 30_000, 40_000]]
    let result = gauge(
      reading: reading(25_000, modelID: "claude-opus-4-7"), settings: settings)
    #expect(result?.ladder == [10_000, 20_000, 30_000, 40_000])
    #expect(result?.passed == [.soft, .status])
    #expect(result?.modelID == "claude-opus-4-7")
  }

  @Test func stateModelBeatsReadingModel() {
    let result = gauge(
      reading: reading(10_000, modelID: "from-reading"), state: state(modelID: "from-state"))
    #expect(result?.modelID == "from-state")
  }

  @Test func warmthPassesThrough() {
    let lifetime = ContextCacheLifetime.fiveMinutes
    let result = gauge(
      reading: reading(10_000, lastActivity: now.addingTimeInterval(-60), cacheLifetime: lifetime))
    #expect(result?.warmth == .warm(secondsLeft: lifetime.seconds - 60))
  }

  @Test func warmthIsUnknownWithoutAReading() {
    #expect(gauge(reading: nil, state: state(tokens: 50_000))?.warmth == .unknown)
  }

  @Test func neitherReadingNorStateGivesNil() {
    #expect(gauge(reading: nil, state: nil) == nil)
  }

  @Test func tokensFallBackToStateLastTokens() {
    let result = gauge(reading: nil, state: state(tokens: 60_000))
    #expect(result?.tokens == 60_000)
    #expect(result?.windowPercent == 30)
  }
}
