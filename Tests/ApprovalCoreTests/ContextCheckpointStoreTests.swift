import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointStoreTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let sessionID = "0b9f3c1e-7a52-4d3a-9c11-5e6f7a8b9c0d"

  private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-context-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @Test func savesAndLoadsRoundTrip() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    var state = ContextCheckpointState.fresh(now: now)
    state.fired = [.soft, .status]
    state.peakTokens = 140_000
    state.lastTokens = 135_000
    state.compactionID = "c1"
    state.modelID = "claude-opus-5-5[1m]"
    state.modelIdentity = ContextModelIdentity(
      modelID: "claude-opus-5-5[1m]", scannedThrough: 812_345)
    state.muted = true
    state.transcriptPath = "/tmp/t.jsonl"
    state.project = "demo"
    state.pendingProcessID = 4242
    try store.save(state, sessionID: sessionID)
    #expect(store.load(sessionID: sessionID) == state)
  }

  @Test func stateWithoutOrWithBadModelIdentityLoadsWithNil() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    let file = directory.appendingPathComponent("\(sessionID).json")
    try Data(#"{"peakTokens":5,"updatedAt":"2027-01-15T08:00:00Z"}"#.utf8).write(to: file)
    #expect(store.load(sessionID: sessionID)?.peakTokens == 5)
    #expect(store.load(sessionID: sessionID)?.modelIdentity == nil)
    try Data(#"{"peakTokens":6,"modelIdentity":"oops","updatedAt":"2027-01-15T08:00:00Z"}"#.utf8)
      .write(to: file)
    #expect(store.load(sessionID: sessionID)?.peakTokens == 6)
    #expect(store.load(sessionID: sessionID)?.modelIdentity == nil)
  }

  @Test func corruptFileLoadsAsNilAndOldFileLoadsWithFreshValues() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    try Data("{not json".utf8).write(to: directory.appendingPathComponent("\(sessionID).json"))
    #expect(store.load(sessionID: sessionID) == nil)
    try Data(#"{"updatedAt":"2027-01-15T08:00:00Z"}"#.utf8)
      .write(to: directory.appendingPathComponent("\(sessionID).json"))
    let loaded = store.load(sessionID: sessionID)
    let expectedDate = Date(timeIntervalSince1970: 1_800_000_000)
    var expected = ContextCheckpointState.fresh(now: loaded?.updatedAt ?? expectedDate)
    expected.updatedAt = loaded?.updatedAt ?? expectedDate
    #expect(loaded == expected)
    #expect(loaded?.updatedAt != nil)
  }

  @Test func rejectsInvalidSessionIDs() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    for invalid in ["../x", "a/b", "", "a.b", "a b"] {
      #expect(ContextCheckpointStore.isValidSessionID(invalid) == false)
      #expect(store.load(sessionID: invalid) == nil)
      #expect(throws: (any Error).self) {
        try store.save(.fresh(now: now), sessionID: invalid)
      }
    }
    #expect(ContextCheckpointStore.isValidSessionID(sessionID))
  }

  @Test func pruneRemovesOldFilesAndKeepsNewOnes() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    try store.save(.fresh(now: now), sessionID: "old")
    try store.save(.fresh(now: now), sessionID: "new")
    try Data().write(to: directory.appendingPathComponent("old.lock"))
    let thirtyOneDays: TimeInterval = 31 * 24 * 3600
    for name in ["old.json", "old.lock"] {
      try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-thirtyOneDays)],
        ofItemAtPath: directory.appendingPathComponent(name).path)
    }
    store.prune(olderThan: 30 * 24 * 3600, now: Date())
    #expect(store.load(sessionID: "old") == nil)
    #expect(store.load(sessionID: "new") != nil)
    #expect(
      !FileManager.default.fileExists(atPath: directory.appendingPathComponent("old.lock").path))
  }

  @Test func pruneKeepsTheLockOfASessionWhoseStateIsStillFresh() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    try store.save(.fresh(now: now), sessionID: "live")
    let lock = directory.appendingPathComponent("live.lock")
    try Data().write(to: lock)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-31 * 24 * 3600)], ofItemAtPath: lock.path)
    store.prune(olderThan: 30 * 24 * 3600, now: Date())
    #expect(FileManager.default.fileExists(atPath: lock.path))
  }

  @Test func pruneAndRemoveAllNeverDeleteAHeldLock() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    let lock = directory.appendingPathComponent("busy.lock")
    let held = try #require(try ExclusiveFileLock.acquire(lock))
    defer { held.release() }
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-31 * 24 * 3600)], ofItemAtPath: lock.path)
    store.prune(olderThan: 30 * 24 * 3600, now: Date())
    #expect(FileManager.default.fileExists(atPath: lock.path))
    store.removeAll()
    #expect(FileManager.default.fileExists(atPath: lock.path))
  }

  @Test func pruneRemovesAnOldTemporaryFileLeftByAFailedSave() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    let old = directory.appendingPathComponent(".a.json.countersign-\(UUID().uuidString).tmp")
    let recent = directory.appendingPathComponent(".b.json.countersign-\(UUID().uuidString).tmp")
    try Data("{".utf8).write(to: old)
    try Data("{".utf8).write(to: recent)
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-31 * 24 * 3600)], ofItemAtPath: old.path)
    store.prune(olderThan: 30 * 24 * 3600, now: Date())
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: recent.path))
  }

  @Test func removeAllLeavesUnrelatedFiles() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    try store.save(.fresh(now: now), sessionID: "a")
    try Data().write(to: directory.appendingPathComponent("a.lock"))
    let unrelated = directory.appendingPathComponent("notes.txt")
    try Data("keep".utf8).write(to: unrelated)
    store.removeAll()
    #expect(store.load(sessionID: "a") == nil)
    #expect(
      !FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.lock").path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
  }

  @Test func withLockRunsBodyAndGivesUpWhileHeld() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    #expect(store.withLock(sessionID: sessionID) { 7 } == 7)
    let held = try ExclusiveFileLock.acquire(
      directory.appendingPathComponent("\(sessionID).lock"))
    #expect(held != nil)
    var ran = false
    let result: Int? = store.withLock(sessionID: sessionID, attempts: 1, interval: 0) {
      ran = true
      return 1
    }
    #expect(result == nil)
    #expect(!ran)
    held?.release()
    #expect(store.withLock(sessionID: sessionID, attempts: 1) { 2 } == 2)
    #expect(store.withLock(sessionID: "../x") { 3 } == nil)
  }

  @Test func sessionIDsIgnoresLockFilesAndInvalidNames() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ContextCheckpointStore(directory: directory)
    try store.save(ContextCheckpointState.fresh(now: now), sessionID: "b-2")
    try store.save(ContextCheckpointState.fresh(now: now), sessionID: "a1")
    try Data().write(to: directory.appendingPathComponent("c3.lock"))
    try Data("{}".utf8).write(to: directory.appendingPathComponent("bad name.json"))
    try Data("{}".utf8).write(to: directory.appendingPathComponent("under_score.json"))
    #expect(store.sessionIDs() == ["a1", "b-2"])
  }
}
