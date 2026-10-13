import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ColdCacheWarningTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func makeStore() throws -> (ContextCheckpointStore, URL) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-cold-cache-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (ContextCheckpointStore(directory: directory), directory)
  }

  private func save(
    _ store: ContextCheckpointStore, id: String, lastTokens: Int = 150_000,
    project: String? = "shop-api", transcript: String? = "/transcripts/session.jsonl"
  ) throws {
    var state = ContextCheckpointState.fresh(now: now)
    state.lastTokens = lastTokens
    state.project = project
    state.transcriptPath = transcript
    try store.save(state, sessionID: id)
  }

  private func reading(
    tokens: Int = 150_000, secondsLeft: TimeInterval? = 600,
    lifetime: ContextCacheLifetime? = .oneHour
  ) -> ContextReading {
    ContextReading(
      tokens: tokens, modelID: nil, hasMillionTokenWindow: false, compactionID: nil,
      lastActivity: secondsLeft.map {
        now.addingTimeInterval($0 - (lifetime ?? .oneHour).seconds)
      },
      cacheLifetime: lifetime)
  }

  private func candidates(
    _ store: ContextCheckpointStore, isIdle: @escaping (String) -> Bool = { _ in true },
    settings: ContextCheckpointSettings = .default,
    read: @escaping (URL) -> ContextReading?
  ) -> [ColdCacheCandidate] {
    ColdCacheWarning.candidates(
      store: store, isIdle: isIdle, settings: settings, now: now, read: read)
  }

  @Test func dueAtSixHundredSecondsLeft() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a")
    let found = candidates(store) { _ in reading(secondsLeft: 600) }
    #expect(found.map(\.sessionID) == ["a"])
    #expect(found.first?.project == "shop-api")
    #expect(found.first?.tokens == 150_000)
    #expect(found.first?.secondsLeft == 600)
  }

  @Test func notDueAtSixHundredAndOneSecondsLeft() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a")
    #expect(candidates(store) { _ in reading(secondsLeft: 601) }.isEmpty)
  }

  @Test func notDueWhenExpiredOrCold() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a")
    #expect(candidates(store) { _ in reading(secondsLeft: 0) }.isEmpty)
    #expect(candidates(store) { _ in reading(secondsLeft: -30) }.isEmpty)
  }

  @Test func notDueWithFiveMinuteCache() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a")
    #expect(candidates(store) { _ in reading(secondsLeft: 200, lifetime: .fiveMinutes) }.isEmpty)
  }

  @Test func notDueBelowTheFirstRung() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a")
    #expect(candidates(store) { _ in reading(tokens: 99_999) }.isEmpty)
  }

  @Test func notDueWhenSessionIsNotIdle() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a")
    #expect(candidates(store, isIdle: { _ in false }, read: { _ in reading() }).isEmpty)
  }

  @Test func notDueWithoutAReadingEvenWhenLastTokensIsLarge() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", lastTokens: 900_000)
    #expect(candidates(store) { _ in nil }.isEmpty)
  }

  @Test func notDueWithoutATranscriptPath() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a", transcript: nil)
    #expect(candidates(store) { _ in reading() }.isEmpty)
  }

  @Test func emptyWhenCheckpointsOrTheCardAreOff() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "a")
    var checkpointsOff = ContextCheckpointSettings.default
    checkpointsOff.enabled = false
    var cardOff = ContextCheckpointSettings.default
    cardOff.coldCacheCard = false
    #expect(candidates(store, settings: checkpointsOff) { _ in reading() }.isEmpty)
    #expect(candidates(store, settings: cardOff) { _ in reading() }.isEmpty)
  }

  @Test func candidatesAreSortedBySecondsLeft() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try save(store, id: "late", transcript: "/transcripts/late.jsonl")
    try save(store, id: "soon", transcript: "/transcripts/soon.jsonl")
    let found = candidates(store) { url in
      reading(secondsLeft: url.lastPathComponent == "soon.jsonl" ? 120 : 500)
    }
    #expect(found.map(\.sessionID) == ["soon", "late"])
  }

  private func registry(_ entries: [String: String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-cold-sessions-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (index, entry) in entries.sorted(by: { $0.key < $1.key }).enumerated() {
      try Data(entry.value.utf8).write(to: directory.appendingPathComponent("\(index).json"))
    }
    return directory
  }

  @Test func idleRequiresALivePidAndIdleStatus() throws {
    let livePID = ProcessInfo.processInfo.processIdentifier
    let directory = try registry([
      "idle": "{\"sessionId\":\"idle\",\"pid\":\(livePID),\"status\":\"idle\"}",
      "busy": "{\"sessionId\":\"busy\",\"pid\":\(livePID),\"status\":\"busy\"}",
      "waiting": "{\"sessionId\":\"waiting\",\"pid\":\(livePID),\"status\":\"waiting\"}",
      "dead": "{\"sessionId\":\"dead\",\"pid\":2147483646,\"status\":\"idle\"}",
    ])
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(ColdCacheWarning.isIdle(sessionID: "idle", sessionsDirectory: directory))
    #expect(!ColdCacheWarning.isIdle(sessionID: "busy", sessionsDirectory: directory))
    #expect(!ColdCacheWarning.isIdle(sessionID: "waiting", sessionsDirectory: directory))
    #expect(!ColdCacheWarning.isIdle(sessionID: "dead", sessionsDirectory: directory))
    #expect(!ColdCacheWarning.isIdle(sessionID: "missing", sessionsDirectory: directory))
  }

  @Test func leadTextRoundsMinutesUp() {
    #expect(
      ColdCacheWarning.leadText(tokens: 640_000, secondsLeft: 540)
        == "640K tokens go cold in 9 min · ")
    #expect(
      ColdCacheWarning.leadText(tokens: 640_000, secondsLeft: 541)
        == "640K tokens go cold in 10 min · ")
    #expect(
      ColdCacheWarning.leadText(tokens: 640_000, secondsLeft: 59)
        == "640K tokens go cold in under a minute · ")
  }

  @Test func ledgerWarnsOncePerIdleStretch() {
    let candidate = ColdCacheCandidate(
      sessionID: "a", project: "shop-api", tokens: 150_000, secondsLeft: 500, lastActivity: now)
    var newer = candidate
    newer.lastActivity = now.addingTimeInterval(60)
    var ledger = ColdCacheWarningLedger()
    #expect(!ledger.isWarned(candidate))
    ledger.markWarned(candidate)
    #expect(ledger.isWarned(candidate))
    #expect(!ledger.isWarned(newer))
    ledger.forget(sessionID: "a")
    #expect(!ledger.isWarned(candidate))
  }
}
