import Foundation
import Testing

@testable import ApprovalCore

@Suite struct WaitingStoreTests {
  private func temporaryStore() -> WaitingStore {
    WaitingStore(
      directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("countersign-waiting-\(UUID().uuidString)"))
  }

  private func removeDirectory(of store: WaitingStore) {
    try? FileManager.default.removeItem(at: store.directory)
  }

  private func record() -> WaitingRecord {
    WaitingRecord(
      host: .claude, sessionID: "c4d2e8f1-7a3b-4c5d-9e6f-1a2b3c4d5e6f", projectName: "shop-api",
      projectPath: "/Users/dev/Projects/shop-api",
      transcriptPath:
        "/Users/dev/.claude/projects/shop-api/c4d2e8f1-7a3b-4c5d-9e6f-1a2b3c4d5e6f.jsonl",
      reason: .handedBack, recordedAt: Date(timeIntervalSinceReferenceDate: 812_345_678.123),
      appBundleID: "com.todesktop.230313mzl4w4u92", appPID: 812, appName: "Cursor",
      agentPID: 4_021, agentStart: 1_790_000_000_123_456)
  }

  @Test func savedRecordLoadsBack() throws {
    let store = temporaryStore()
    defer { removeDirectory(of: store) }
    let saved = record()

    let file = try store.save(saved)

    #expect(file.lastPathComponent == "claude-c4d2e8f1-7a3b-4c5d-9e6f-1a2b3c4d5e6f.json")
    #expect(file == store.recordFile(host: .claude, sessionID: saved.sessionID))
    #expect(store.load(file) == saved)
    #expect(
      store.lockFile(for: saved).lastPathComponent
        == "claude-c4d2e8f1-7a3b-4c5d-9e6f-1a2b3c4d5e6f.lock")
    #expect(store.slotLockFile(2).lastPathComponent == "slot-2.lock")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
    #expect(leftovers == [file.lastPathComponent])

    store.delete(file)
    #expect(store.load(file) == nil)
  }

  @Test func keyReplacesUnsafeCharactersAndCapsTheLength() {
    #expect(WaitingStore.key(for: "a/b c:d.e_f-9") == "a_b_c_d.e_f-9")
    #expect(WaitingStore.key(for: "../é") == "..__")
    let long = String(repeating: "x", count: 100)
    #expect(WaitingStore.key(for: long) == String(repeating: "x", count: 80))
    let record = WaitingRecord(
      host: .cursor, sessionID: "a/b", projectName: "p", projectPath: "/p", transcriptPath: nil,
      reason: .turnEnded, recordedAt: Date(timeIntervalSinceReferenceDate: 0))
    #expect(temporaryStore().recordFile(for: record).lastPathComponent == "cursor-a_b.json")
  }

  @Test func corruptFileLoadsAsNil() throws {
    let store = temporaryStore()
    defer { removeDirectory(of: store) }
    let file = store.recordFile(host: .codex, sessionID: "d9e0f1a2")
    #expect(store.load(file) == nil)

    try FileManager.default.createDirectory(
      at: store.directory, withIntermediateDirectories: true)
    try Data("{\"host\":\"codex\"".utf8).write(to: file)

    #expect(store.load(file) == nil)
  }

  @Test func deleteRecordRemovesAnExistingRecord() throws {
    let store = temporaryStore()
    defer { removeDirectory(of: store) }
    let saved = record()
    let file = try store.save(saved)

    #expect(store.deleteRecord(host: saved.host, sessionID: saved.sessionID))
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func deleteRecordIsQuietForAMissingRecord() {
    let store = temporaryStore()
    defer { removeDirectory(of: store) }

    #expect(!store.deleteRecord(host: .codex, sessionID: "missing"))
  }
}
