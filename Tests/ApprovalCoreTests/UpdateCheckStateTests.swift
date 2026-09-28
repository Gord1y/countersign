import Foundation
import Testing

@testable import ApprovalCore

@Suite struct UpdateCheckStateTests {
  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-update-check-\(UUID().uuidString)")
      .appendingPathComponent("nested")
      .appendingPathComponent("update-check.json")
  }

  private func removeContainer(of file: URL) {
    let container = file.deletingLastPathComponent().deletingLastPathComponent()
    try? FileManager.default.removeItem(at: container)
  }

  @Test func loadReturnsNilWhenTheFileIsMissing() {
    #expect(UpdateCheckStateStore.load(file: temporaryFile()) == nil)
  }

  @Test func savesAndLoadsANewerAvailableOutcome() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let state = UpdateCheckState(
      lastAttempt: Date(timeIntervalSince1970: 1_700_000_000),
      outcome: .newerAvailable(version: "0.2.0"))

    try UpdateCheckStateStore.save(state, to: file)
    let loaded = UpdateCheckStateStore.load(file: file)

    #expect(loaded == state)
  }

  @Test func savesAndLoadsAnUpToDateOutcome() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let state = UpdateCheckState(
      lastAttempt: Date(timeIntervalSince1970: 1_700_000_000), outcome: .upToDate)

    try UpdateCheckStateStore.save(state, to: file)

    #expect(UpdateCheckStateStore.load(file: file) == state)
  }

  @Test func savesAndLoadsAnUnknownOutcome() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let state = UpdateCheckState(
      lastAttempt: Date(timeIntervalSince1970: 1_700_000_000), outcome: .unknown(reason: "HTTP 404")
    )

    try UpdateCheckStateStore.save(state, to: file)

    #expect(UpdateCheckStateStore.load(file: file) == state)
  }

  @Test func saveOverwritesAPreviousState() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try UpdateCheckStateStore.save(
      UpdateCheckState(lastAttempt: Date(timeIntervalSince1970: 1), outcome: .upToDate), to: file)
    let second = UpdateCheckState(
      lastAttempt: Date(timeIntervalSince1970: 2), outcome: .newerAvailable(version: "0.3.0"))

    try UpdateCheckStateStore.save(second, to: file)

    #expect(UpdateCheckStateStore.load(file: file) == second)
  }

  @Test func loadReturnsNilForCorruptedJSON() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: file)

    #expect(UpdateCheckStateStore.load(file: file) == nil)
  }

  @Test func loadReturnsNilWhenLastAttemptIsMissing() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"result": {"kind": "upToDate"}}"#.utf8).write(to: file)

    #expect(UpdateCheckStateStore.load(file: file) == nil)
  }

  @Test func loadReturnsNilForAnUnknownResultKind() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"lastAttempt": 1, "result": {"kind": "mystery"}}"#.utf8).write(to: file)

    #expect(UpdateCheckStateStore.load(file: file) == nil)
  }

  @Test func loadReturnsNilWhenNewerAvailableHasNoVersion() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"lastAttempt": 1, "result": {"kind": "newerAvailable"}}"#.utf8).write(to: file)

    #expect(UpdateCheckStateStore.load(file: file) == nil)
  }
}
