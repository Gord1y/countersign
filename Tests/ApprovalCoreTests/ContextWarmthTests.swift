import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextWarmthTests {
  private let lastActivity = Date(timeIntervalSince1970: 1_800_000_000)

  private func reading(
    lastActivity: Date?, cacheLifetime: ContextCacheLifetime?
  ) -> ContextReading {
    ContextReading(
      tokens: 100_000, modelID: nil, hasMillionTokenWindow: false, compactionID: nil,
      lastActivity: lastActivity, cacheLifetime: cacheLifetime)
  }

  @Test func lifetimesAreFiveMinutesAndOneHour() {
    #expect(ContextCacheLifetime.fiveMinutes.seconds == 300)
    #expect(ContextCacheLifetime.oneHour.seconds == 3600)
  }

  @Test func warmReportsTheSecondsLeft() {
    let value = reading(lastActivity: lastActivity, cacheLifetime: .fiveMinutes)
    let now = lastActivity.addingTimeInterval(100)
    #expect(ContextWarmth.of(value, now: now) == .warm(secondsLeft: 200))
  }

  @Test func coldExactlyAtExpiry() {
    let value = reading(lastActivity: lastActivity, cacheLifetime: .oneHour)
    let now = lastActivity.addingTimeInterval(3600)
    #expect(ContextWarmth.of(value, now: now) == .cold)
  }

  @Test func coldAfterExpiry() {
    let value = reading(lastActivity: lastActivity, cacheLifetime: .fiveMinutes)
    let now = lastActivity.addingTimeInterval(301)
    #expect(ContextWarmth.of(value, now: now) == .cold)
  }

  @Test func unknownWhenEitherFieldIsMissing() {
    let now = lastActivity.addingTimeInterval(10)
    #expect(
      ContextWarmth.of(reading(lastActivity: nil, cacheLifetime: .oneHour), now: now) == .unknown)
    #expect(
      ContextWarmth.of(reading(lastActivity: lastActivity, cacheLifetime: nil), now: now)
        == .unknown)
    #expect(ContextWarmth.of(reading(lastActivity: nil, cacheLifetime: nil), now: now) == .unknown)
  }
}
