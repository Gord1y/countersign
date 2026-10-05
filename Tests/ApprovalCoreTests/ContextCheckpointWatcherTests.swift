import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointWatcherTests {
  private final class Clock: @unchecked Sendable {
    var current = Date(timeIntervalSince1970: 5_000)
  }

  private final class ParentBox: @unchecked Sendable {
    var pid: Int32 = 100
  }

  private struct Workspace {
    let directory: URL
    let transcript: URL
    let store: ContextCheckpointStore

    init(transcriptContents: String) throws {
      directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("countersign-watcher-\(UUID().uuidString)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      transcript = directory.appendingPathComponent("session.jsonl")
      try Data(transcriptContents.utf8).write(to: transcript)
      store = ContextCheckpointStore(directory: directory.appendingPathComponent("state"))
    }

    func append(_ text: String) throws {
      let handle = try FileHandle(forWritingTo: transcript)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(text.utf8))
    }

    func remove() {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  private func compactedLines() throws -> [String] {
    let data = try FixtureLoader.data("claude-transcript-compacted", withExtension: "jsonl")
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
  }

  private func watcher(
    _ workspace: Workspace, clock: Clock, parent: ParentBox
  ) -> ContextCheckpointWatcher {
    ContextCheckpointWatcher(
      transcriptURL: workspace.transcript, sessionID: "session-1", processID: 42,
      store: workspace.store, baselineCompactionID: nil, now: { clock.current },
      parentPID: { parent.pid })
  }

  @Test func aChangedParentMeansTheParentExited() throws {
    let lines = try compactedLines()
    let workspace = try Workspace(transcriptContents: lines[0] + "\n")
    defer { workspace.remove() }
    let clock = Clock()
    let parent = ParentBox()
    let watcher = watcher(workspace, clock: clock, parent: parent)

    #expect(watcher.poll() == nil)
    parent.pid = 1
    #expect(watcher.poll() == .parentExited)
    parent.pid = 100
    #expect(watcher.poll() == .parentExited)
  }

  @Test func anotherProcessInTheStoredStateMeansSuperseded() throws {
    let lines = try compactedLines()
    let workspace = try Workspace(transcriptContents: lines[0] + "\n")
    defer { workspace.remove() }
    let clock = Clock()
    let watcher = watcher(workspace, clock: clock, parent: ParentBox())

    var state = ContextCheckpointState.fresh(now: clock.current)
    state.pendingProcessID = 42
    try workspace.store.save(state, sessionID: "session-1")
    #expect(watcher.poll() == nil)

    state.pendingProcessID = 43
    try workspace.store.save(state, sessionID: "session-1")
    #expect(watcher.poll() == .superseded)
  }

  @Test func aCompactionBoundaryAppendedLaterMeansCompactedOnceTwoSecondsPassed() throws {
    let lines = try compactedLines()
    let workspace = try Workspace(transcriptContents: lines[0] + "\n")
    defer { workspace.remove() }
    let clock = Clock()
    let watcher = watcher(workspace, clock: clock, parent: ParentBox())

    try workspace.append(lines[1] + "\n")
    clock.current = clock.current.addingTimeInterval(1)
    #expect(watcher.poll() == nil)

    clock.current = clock.current.addingTimeInterval(1)
    #expect(watcher.poll() == .compacted)
  }

  @Test func anUnchangedTranscriptKeepsWatching() throws {
    let lines = try compactedLines()
    let workspace = try Workspace(transcriptContents: lines[0] + "\n")
    defer { workspace.remove() }
    let clock = Clock()
    let watcher = watcher(workspace, clock: clock, parent: ParentBox())

    clock.current = clock.current.addingTimeInterval(10)
    #expect(watcher.poll() == nil)
    clock.current = clock.current.addingTimeInterval(10)
    #expect(watcher.poll() == nil)
  }

  @Test func aMissingTranscriptKeepsWatching() throws {
    let workspace = try Workspace(transcriptContents: "")
    defer { workspace.remove() }
    let clock = Clock()
    let watcher = ContextCheckpointWatcher(
      transcriptURL: nil, sessionID: "session-1", processID: 42, store: workspace.store,
      baselineCompactionID: nil, now: { clock.current }, parentPID: { 100 })

    clock.current = clock.current.addingTimeInterval(10)
    #expect(watcher.poll() == nil)
  }
}
