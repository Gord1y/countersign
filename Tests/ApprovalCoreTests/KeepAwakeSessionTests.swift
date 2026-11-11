import Foundation
import Testing

@testable import ApprovalCore

@Suite struct KeepAwakeSessionTests {
  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-keepawake-\(UUID().uuidString)")
      .appendingPathComponent("nested")
      .appendingPathComponent("keep-awake-session")
  }

  private func removeContainer(of file: URL) {
    let container = file.deletingLastPathComponent().deletingLastPathComponent()
    try? FileManager.default.removeItem(at: container)
  }

  @Test func currentIsNilWhenTheFileIsMissing() {
    let file = temporaryFile()
    #expect(KeepAwakeSession(file: file).current() == nil)
  }

  @Test func startThenCurrentReturnsTheDate() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let session = KeepAwakeSession(file: file)
    let end = Date().addingTimeInterval(600)

    try session.start(.at(end))

    let stored = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    #expect(Int64(stored) == Int64(end.timeIntervalSince1970.rounded()))
    #expect(
      session.current() == .at(Date(timeIntervalSince1970: end.timeIntervalSince1970.rounded())))
  }

  @Test func foreverRoundTrips() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let session = KeepAwakeSession(file: file)

    try session.start(.untilTurnedOff)

    #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self) == "forever")
    #expect(session.current() == .untilTurnedOff)
  }

  @Test func aDateNotAfterNowIsNil() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let session = KeepAwakeSession(file: file)
    let end = Date(timeIntervalSince1970: 1_700_000_000)

    try session.start(.at(end))

    #expect(session.current(now: end) == nil)
    #expect(session.current(now: end.addingTimeInterval(1)) == nil)
    #expect(session.current(now: end.addingTimeInterval(-1)) == .at(end))
  }

  @Test func malformedTextIsNil() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("later".utf8).write(to: file)

    #expect(KeepAwakeSession(file: file).current() == nil)
  }

  @Test func clearRemovesTheFile() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let session = KeepAwakeSession(file: file)
    try session.start(.untilTurnedOff)

    try session.clear()

    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(session.current() == nil)
  }

  @Test func clearOfAMissingFileDoesNotThrow() throws {
    let file = temporaryFile()
    try KeepAwakeSession(file: file).clear()
  }

  @Test func startReplacesTheEarlierSession() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let session = KeepAwakeSession(file: file)
    try session.start(.untilTurnedOff)
    let end = Date().addingTimeInterval(600)

    try session.start(.at(end))

    #expect(
      session.current() == .at(Date(timeIntervalSince1970: end.timeIntervalSince1970.rounded())))
  }

  @Test func startLeavesNoTemporaryFileBehind() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let session = KeepAwakeSession(file: file)

    try session.start(.untilTurnedOff)
    try session.start(.at(Date().addingTimeInterval(60)))

    let names = try FileManager.default.contentsOfDirectory(
      atPath: file.deletingLastPathComponent().path)
    #expect(names == ["keep-awake-session"])
  }

  @Test func initFromPathsUsesTheSessionFile() {
    let paths = AppPaths(home: URL(fileURLWithPath: "/Users/dev"))
    #expect(KeepAwakeSession(paths: paths).file == paths.keepAwakeSessionFile)
  }
}
