import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextUsageReaderTests {
  private static let boundaryID = "dec5892f-eb15-4d3a-9c54-9a62631aba5f"

  private func fixtureLines(_ name: String) throws -> [Substring] {
    let data = try FixtureLoader.data(name, withExtension: "jsonl")
    return String(decoding: data, as: UTF8.self).split(
      separator: "\n", omittingEmptySubsequences: true)
  }

  private func temporaryFile(_ contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "context-usage-\(UUID().uuidString).jsonl")
    try Data(contents.utf8).write(to: url)
    return url
  }

  @Test func readsTokensAndModelFromUsageFixture() throws {
    let reading = ContextUsageReader.reading(fromLines: try fixtureLines("claude-transcript-usage"))
    #expect(
      reading
        == ContextReading(
          tokens: 34400, modelID: "claude-haiku-4-5", hasMillionTokenWindow: false,
          compactionID: nil))
  }

  @Test func laterMillionTokenIdentityMarksTheWindow() throws {
    let lines =
      try fixtureLines("claude-transcript-usage") + fixtureLines("claude-transcript-model-1m")
    let reading = ContextUsageReader.reading(fromLines: lines)
    #expect(reading?.modelID == "claude-opus-5-5[1m]")
    #expect(reading?.hasMillionTokenWindow == true)
    #expect(reading?.tokens == 34400)
  }

  @Test func usageAfterCompactionWins() throws {
    let reading = ContextUsageReader.reading(
      fromLines: try fixtureLines("claude-transcript-compacted"))
    #expect(reading?.tokens == 87997)
    #expect(reading?.compactionID == Self.boundaryID)
  }

  @Test func boundaryAfterLatestUsageSuppliesPostTokens() throws {
    let lines = Array(try fixtureLines("claude-transcript-compacted").prefix(2))
    let reading = ContextUsageReader.reading(fromLines: lines)
    #expect(reading?.tokens == 26309)
    #expect(reading?.compactionID == Self.boundaryID)
  }

  @Test func skipsNonJSONLinesAndCutOffFinalLine() throws {
    let usageLines = try fixtureLines("claude-transcript-usage")
    let mainRow = usageLines[1]
    let cutOff = mainRow.prefix(mainRow.count / 2)
    let lines: [Substring] = [mainRow, "this is not json", cutOff]
    #expect(ContextUsageReader.reading(fromLines: lines)?.tokens == 34400)
  }

  @Test func skipsUsageRowWithNonIntegerField() throws {
    let mainRow = try fixtureLines("claude-transcript-usage")[1]
    let broken = mainRow.replacingOccurrences(
      of: "\"input_tokens\":10,", with: "\"input_tokens\":\"10\",")
    #expect(broken != String(mainRow))
    let lines: [Substring] = [mainRow, Substring(broken)]
    #expect(ContextUsageReader.reading(fromLines: lines)?.tokens == 34400)
  }

  @Test func tokensAboveStandardWindowImplyMillionTokenWindow() throws {
    let lines = Array(try fixtureLines("claude-transcript-compacted").prefix(1))
    let reading = ContextUsageReader.reading(fromLines: lines)
    #expect(reading?.tokens == 626118)
    #expect(reading?.hasMillionTokenWindow == true)
  }

  @Test func readsWholeFileWhenTheTailHoldsNoUsage() throws {
    let mainRow = try fixtureLines("claude-transcript-usage")[1]
    let filler = String(repeating: "{\"type\":\"last-prompt\"}\n", count: 30_000)
    #expect(filler.utf8.count > 600_000)
    let url = try temporaryFile(String(mainRow) + "\n" + filler)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ContextUsageReader.read(transcriptURL: url)?.tokens == 34400)
  }

  @Test func returnsNilForMissingEmptyAndUsagelessFiles() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(
      "context-usage-missing-\(UUID().uuidString).jsonl")
    #expect(ContextUsageReader.read(transcriptURL: missing) == nil)

    let empty = try temporaryFile("")
    defer { try? FileManager.default.removeItem(at: empty) }
    #expect(ContextUsageReader.read(transcriptURL: empty) == nil)

    let usageless = try temporaryFile("{\"type\":\"last-prompt\"}\n{\"type\":\"last-prompt\"}\n")
    defer { try? FileManager.default.removeItem(at: usageless) }
    #expect(ContextUsageReader.read(transcriptURL: usageless) == nil)
  }
}
