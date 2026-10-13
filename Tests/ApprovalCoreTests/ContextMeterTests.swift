import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextMeterTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func makeStore() throws -> (ContextCheckpointStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-meter-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (ContextCheckpointStore(directory: directory), directory)
  }

  private func save(
    _ store: ContextCheckpointStore, id: String, tokens: Int, project: String? = "shop-api",
    transcript: String? = nil
  ) throws {
    var state = ContextCheckpointState.fresh(now: now)
    state.lastTokens = tokens
    state.project = project
    state.transcriptPath = transcript
    try store.save(state, sessionID: id)
  }

  private func reading(_ tokens: Int) -> ContextReading {
    ContextReading(tokens: tokens, modelID: nil, hasMillionTokenWindow: false, compactionID: nil)
  }

  @Test func deadSessionIsLeftOut() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "alive", tokens: 50_000)
    try save(store, id: "dead", tokens: 90_000)
    let rows = ContextMeter.rows(store: store, isLive: { $0 == "alive" }, read: { _ in nil })
    #expect(rows.map(\.sessionID) == ["alive"])
  }

  @Test func freshReadingBeatsLastTokens() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", tokens: 50_000, transcript: "/tmp/a.jsonl")
    let rows = ContextMeter.rows(
      store: store, isLive: { _ in true },
      read: { $0.path == "/tmp/a.jsonl" ? reading(212_000) : nil })
    #expect(rows.map(\.tokens) == [212_000])
  }

  @Test func failedReadFallsBackToLastTokens() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", tokens: 50_000, transcript: "/tmp/a.jsonl")
    try save(store, id: "b", tokens: 60_000)
    let rows = ContextMeter.rows(store: store, isLive: { _ in true }, read: { _ in nil })
    #expect(rows.map(\.tokens) == [60_000, 50_000])
  }

  @Test func rowsAreSortedLargestFirstAndCappedAtEight() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    for index in 1...10 {
      try save(store, id: "s\(index)", tokens: index * 10_000)
    }
    let rows = ContextMeter.rows(store: store, isLive: { _ in true }, read: { _ in nil })
    #expect(rows.count == ContextMeter.maximumRows)
    #expect(
      rows.map(\.tokens) == [100_000, 90_000, 80_000, 70_000, 60_000, 50_000, 40_000, 30_000])
  }

  @Test func titleShowsProjectAndTokens() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", tokens: 212_000)
    let rows = ContextMeter.rows(store: store, isLive: { _ in true }, read: { _ in nil })
    #expect(rows.first?.title == "shop-api · 212K tokens · 21%")
    #expect(rows.first?.project == "shop-api")
  }

  private func warmthRow(
    secondsSinceActivity: TimeInterval, lifetime: ContextCacheLifetime?, tokens: Int = 100_000
  ) throws -> ContextMeterRow? {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", tokens: tokens, transcript: "/tmp/a.jsonl")
    let value = ContextReading(
      tokens: tokens, modelID: nil, hasMillionTokenWindow: false, compactionID: nil,
      lastActivity: now.addingTimeInterval(-secondsSinceActivity), cacheLifetime: lifetime)
    return ContextMeter.rows(store: store, isLive: { _ in true }, now: now, read: { _ in value })
      .first
  }

  @Test func warmTitleRoundsMinutesUp() throws {
    let row = try warmthRow(secondsSinceActivity: 100, lifetime: .fiveMinutes)
    #expect(row?.title == "shop-api · 100K tokens · 50% · warm, 4 min left")
    #expect(row?.warmth == .warm(secondsLeft: 200))
    let exact = try warmthRow(secondsSinceActivity: 120, lifetime: .fiveMinutes)
    #expect(exact?.title == "shop-api · 100K tokens · 50% · warm, 3 min left")
  }

  @Test func warmTitleUnderAMinute() throws {
    let row = try warmthRow(secondsSinceActivity: 250, lifetime: .fiveMinutes)
    #expect(row?.title == "shop-api · 100K tokens · 50% · warm, under a minute left")
  }

  @Test func coldTitle() throws {
    let row = try warmthRow(secondsSinceActivity: 300, lifetime: .fiveMinutes)
    #expect(row?.title == "shop-api · 100K tokens · 50% · cold")
    #expect(row?.warmth == .cold)
  }

  @Test func unknownWarmthTitleHasNoSuffix() throws {
    let row = try warmthRow(secondsSinceActivity: 10, lifetime: nil)
    #expect(row?.title == "shop-api · 100K tokens · 50%")
    #expect(row?.warmth == .unknown)
  }

  @Test func windowPercentUsesTwoHundredKForStandardAndOneMillionForLargeWindows() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "standard", tokens: 150_000)
    try save(store, id: "tagged", tokens: 150_000)
    var tagged = try #require(store.load(sessionID: "tagged"))
    tagged.modelID = "claude-opus-5-5[1m]"
    try store.save(tagged, sessionID: "tagged")
    try save(store, id: "over", tokens: 400_000)
    let rows = ContextMeter.rows(store: store, isLive: { _ in true }, read: { _ in nil })
    let percents = Dictionary(uniqueKeysWithValues: rows.map { ($0.sessionID, $0.windowPercent) })
    #expect(percents == ["standard": 75, "tagged": 15, "over": 40])
  }

  @Test func missingProjectFallsBackToClaudeCode() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", tokens: 130_000, project: nil)
    let rows = ContextMeter.rows(store: store, isLive: { _ in true }, read: { _ in nil })
    #expect(rows.first?.title == "Claude Code · 130K tokens · 65%")
  }

  @Test func unknownSessionIsNotLive() {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-no-sessions-\(UUID().uuidString)")
    #expect(!ContextMeter.isLive(sessionID: "a", sessionsDirectory: missing))
  }

  @Test func sessionWithLivePidIsLiveAndDeadPidIsNot() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-sessions-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let livePID = ProcessInfo.processInfo.processIdentifier
    try Data("{\"sessionId\":\"live\",\"pid\":\(livePID)}".utf8)
      .write(to: directory.appendingPathComponent("1.json"))
    try Data("{\"sessionId\":\"gone\",\"pid\":2147483646}".utf8)
      .write(to: directory.appendingPathComponent("2.json"))
    try Data("{\"sessionId\":\"nopid\"}".utf8)
      .write(to: directory.appendingPathComponent("3.json"))
    #expect(ContextMeter.isLive(sessionID: "live", sessionsDirectory: directory))
    #expect(!ContextMeter.isLive(sessionID: "gone", sessionsDirectory: directory))
    #expect(!ContextMeter.isLive(sessionID: "nopid", sessionsDirectory: directory))
  }
}
