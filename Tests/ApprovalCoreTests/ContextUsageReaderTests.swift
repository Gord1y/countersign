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

  @Test func onlyTheHookReadFallsBackToTheWholeFileWhenTheTailHoldsNoUsage() throws {
    let mainRow = try fixtureLines("claude-transcript-usage")[1]
    let filler = String(repeating: "{\"type\":\"last-prompt\"}\n", count: 30_000)
    #expect(filler.utf8.count > 600_000)
    let url = try temporaryFile(String(mainRow) + "\n" + filler)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ContextUsageReader.read(transcriptURL: url, identity: nil)?.reading.tokens == 34400)
    #expect(ContextUsageReader.read(transcriptURL: url) == nil)
  }

  private func paddingRows(bytes: Int) -> String {
    let shortRow = "{\"type\":\"last-prompt\"}\n"
    let shortRows = bytes / shortRow.utf8.count - 3
    let rest = bytes - shortRows * shortRow.utf8.count
    let longRowOverhead = "{\"type\":\"last-prompt\",\"p\":\"\"}\n".utf8.count
    let longRow =
      "{\"type\":\"last-prompt\",\"p\":\""
      + String(repeating: "x", count: rest - longRowOverhead) + "\"}\n"
    return String(repeating: shortRow, count: shortRows) + longRow
  }

  private func identityRow(modelID: String) throws -> String {
    let row = try fixtureLines("claude-transcript-model-1m")[0]
    return row.replacingOccurrences(of: "claude-opus-5-5[1m]", with: modelID) + "\n"
  }

  private func usageRow() throws -> String {
    String(try fixtureLines("claude-transcript-usage")[1]) + "\n"
  }

  @Test func findsAnIdentityRowBeyondTheTail() throws {
    let contents =
      try identityRow(modelID: "claude-opus-5-5[1m]") + paddingRows(bytes: 640_000)
      + usageRow()
    let url = try temporaryFile(contents)
    defer { try? FileManager.default.removeItem(at: url) }
    let result = ContextUsageReader.read(transcriptURL: url, identity: nil, chunkBytes: 4096)
    #expect(result?.reading.tokens == 34400)
    #expect(result?.reading.hasMillionTokenWindow == true)
    #expect(result?.reading.modelID == "claude-opus-5-5[1m]")
    #expect(result?.identity.modelID == "claude-opus-5-5[1m]")
    #expect(result?.identity.scannedThrough == UInt64(contents.utf8.count))
  }

  @Test func findsAnIdentityRowThatStraddlesAChunkBoundary() throws {
    let identity = try identityRow(modelID: "claude-opus-5-5[1m]")
    let usage = try usageRow()
    let afterIdentity = ContextUsageReader.tailBytes - identity.utf8.count / 2
    let contents =
      identity + paddingRows(bytes: afterIdentity - usage.utf8.count) + usage
    let url = try temporaryFile(contents)
    defer { try? FileManager.default.removeItem(at: url) }
    for chunkBytes in [64, 97, 100, 101, 333, 4096] {
      let result = ContextUsageReader.read(
        transcriptURL: url, identity: nil, chunkBytes: chunkBytes)
      #expect(result?.reading.hasMillionTokenWindow == true)
      #expect(result?.identity.modelID == "claude-opus-5-5[1m]")
    }
  }

  @Test func cachedIdentityIsUsedAndTheScanStopsAtIt() throws {
    let older = try identityRow(modelID: "claude-haiku-4-5")
    let contents = older + paddingRows(bytes: 640_000) + (try usageRow())
    let url = try temporaryFile(contents)
    defer { try? FileManager.default.removeItem(at: url) }
    let cached = ContextModelIdentity(
      modelID: "claude-opus-5-5[1m]", scannedThrough: UInt64(older.utf8.count))
    let result = ContextUsageReader.read(transcriptURL: url, identity: cached, chunkBytes: 4096)
    #expect(result?.reading.modelID == "claude-opus-5-5[1m]")
    #expect(result?.reading.hasMillionTokenWindow == true)
    #expect(
      result?.identity
        == ContextModelIdentity(
          modelID: "claude-opus-5-5[1m]", scannedThrough: UInt64(contents.utf8.count)))
  }

  @Test func cachedIdentityPastTheFileSizeIsIgnored() throws {
    let contents =
      try identityRow(modelID: "claude-haiku-4-5") + paddingRows(bytes: 640_000) + usageRow()
    let url = try temporaryFile(contents)
    defer { try? FileManager.default.removeItem(at: url) }
    let cached = ContextModelIdentity(
      modelID: "claude-opus-5-5[1m]", scannedThrough: UInt64(contents.utf8.count) + 1000)
    let result = ContextUsageReader.read(transcriptURL: url, identity: cached, chunkBytes: 4096)
    #expect(result?.reading.modelID == "claude-haiku-4-5")
    #expect(result?.reading.hasMillionTokenWindow == false)
    #expect(result?.identity.modelID == "claude-haiku-4-5")
    #expect(result?.identity.scannedThrough == UInt64(contents.utf8.count))
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
