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
    #expect(rows.first?.title == "shop-api · 212K tokens")
    #expect(rows.first?.project == "shop-api")
  }

  @Test func missingProjectFallsBackToClaudeCode() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", tokens: 130_000, project: nil)
    let rows = ContextMeter.rows(store: store, isLive: { _ in true }, read: { _ in nil })
    #expect(rows.first?.title == "Claude Code · 130K tokens")
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
