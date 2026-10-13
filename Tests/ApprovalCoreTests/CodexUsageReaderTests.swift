import Foundation
import Testing

@testable import ApprovalCore

@Suite struct CodexUsageReaderTests {
  private func fixtureLines() throws -> [String] {
    let data = try FixtureLoader.data("codex-rollout-token-count", withExtension: "jsonl")
    return String(decoding: data, as: UTF8.self).split(
      separator: "\n", omittingEmptySubsequences: true
    ).map(String.init)
  }

  @Test func theFixtureGivesTheLatestRequestsInputAndWindow() throws {
    let reading = try #require(CodexUsageReader.reading(fromLines: try fixtureLines()))
    #expect(reading.tokens == 20125)
    #expect(reading.windowTokens == 258400)
    let expected = ISO8601DateFormatter()
    expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(reading.timestamp == expected.date(from: "2026-10-13T10:27:25.977Z"))
  }

  @Test func onlyTheFirstLineGivesItsOwnInput() throws {
    let reading = try #require(
      CodexUsageReader.reading(fromLines: Array(try fixtureLines().prefix(1))))
    #expect(reading.tokens == 19990)
  }

  @Test func aGarbageLastLineIsSkipped() throws {
    let reading = try #require(
      CodexUsageReader.reading(fromLines: try fixtureLines() + ["not json {"]))
    #expect(reading.tokens == 20125)
  }

  @Test func noLinesGiveNothing() {
    #expect(CodexUsageReader.reading(fromLines: []) == nil)
  }

  @Test func aMissingFileGivesNothing() {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(
      "codex-usage-missing-\(UUID().uuidString).jsonl")
    #expect(CodexUsageReader.read(rolloutURL: missing) == nil)
  }
}
