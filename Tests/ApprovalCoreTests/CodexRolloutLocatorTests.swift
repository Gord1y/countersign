import Foundation
import Testing

@testable import ApprovalCore

@Suite struct CodexRolloutLocatorTests {
  private let sessionID = "01a0e51e-f14e-7730-902a-072ff0b4dc35"

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-rollouts-\(UUID().uuidString)")
  }

  @discardableResult
  private func writeRollout(
    in root: URL, day: String, sessionID: String, time: String = "2026-09-28T02-06-45"
  ) throws -> String {
    let folder = root.appendingPathComponent(day)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("rollout-\(time)-\(sessionID).jsonl")
    try Data("{}\n".utf8).write(to: file)
    return file.path
  }

  private func canonical(_ path: String?) -> String? {
    path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
  }

  @Test func findsTheFileInTodaysFolder() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let expected = try writeRollout(in: root, day: "2026/09/28", sessionID: sessionID)
    try writeRollout(in: root, day: "2026/09/28", sessionID: "other-session")

    let found = CodexRolloutLocator.find(sessionID: sessionID, sessionsDirectory: root)
    #expect(canonical(found) == canonical(expected))
  }

  @Test func findsTheFileInAnOlderDayFolder() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let expected = try writeRollout(in: root, day: "2026/08/30", sessionID: sessionID)
    try writeRollout(in: root, day: "2026/09/28", sessionID: "other-session")
    try writeRollout(in: root, day: "2026/09/27", sessionID: "another-session")

    let found = CodexRolloutLocator.find(sessionID: sessionID, sessionsDirectory: root)
    #expect(canonical(found) == canonical(expected))
  }

  @Test func returnsNilPastMaxDays() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeRollout(in: root, day: "2026/09/01", sessionID: sessionID)
    try writeRollout(in: root, day: "2026/09/28", sessionID: "other-session")
    try writeRollout(in: root, day: "2026/09/27", sessionID: "another-session")

    #expect(
      CodexRolloutLocator.find(sessionID: sessionID, sessionsDirectory: root, maxDays: 2) == nil)
    #expect(
      CodexRolloutLocator.find(sessionID: sessionID, sessionsDirectory: root, maxDays: 3) != nil)
  }

  @Test func skipsNonNumericFolderNames() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeRollout(in: root, day: "archive/09/28", sessionID: sessionID)
    try writeRollout(in: root, day: "2026/backup/28", sessionID: sessionID)
    try writeRollout(in: root, day: "2026/09/notes", sessionID: sessionID)

    #expect(CodexRolloutLocator.find(sessionID: sessionID, sessionsDirectory: root) == nil)
  }

  @Test func returnsNilForAMissingSessionsFolder() {
    let root = temporaryDirectory()

    #expect(CodexRolloutLocator.find(sessionID: sessionID, sessionsDirectory: root) == nil)
  }
}
