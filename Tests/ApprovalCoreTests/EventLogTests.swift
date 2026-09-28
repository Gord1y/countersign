import Foundation
import Testing

@testable import ApprovalCore

@Suite struct EventLogTests {
  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-eventlog-\(UUID().uuidString)")
      .appendingPathComponent("nested")
      .appendingPathComponent("countersign.log")
  }

  private func removeContainer(of file: URL) {
    let container = file.deletingLastPathComponent().deletingLastPathComponent()
    try? FileManager.default.removeItem(at: container)
  }

  @Test func writeCreatesTheDirectoryAndAppendsALine() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let log = EventLog(file: file)

    log.write("hello")

    let contents = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 2)
    #expect(lines[1].isEmpty)
    let line = String(lines[0])
    let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z \[\d+\] hello$"#
    #expect(line.range(of: pattern, options: .regularExpression) != nil)
    #expect(line.contains("[\(getpid())]"))
  }

  @Test func writeAppendsAcrossCalls() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let log = EventLog(file: file)

    log.write("one")
    log.write("two")

    let contents = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    let lines = contents.split(separator: "\n").map(String.init)
    #expect(lines.count == 2)
    #expect(lines[0].hasSuffix("one"))
    #expect(lines[1].hasSuffix("two"))
  }

  @Test func rotateIfNeededOnAMissingFileDoesNothing() {
    let file = temporaryFile()
    let log = EventLog(file: file, maxBytes: 10)

    log.rotateIfNeeded()

    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func rotateIfNeededLeavesASmallFileAlone() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let log = EventLog(file: file, maxBytes: 1_048_576)

    log.write("small")
    log.rotateIfNeeded()

    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(!FileManager.default.fileExists(atPath: file.path + ".1"))
  }

  @Test func rotateIfNeededRenamesAnOversizedFileAndReplacesAnOldRotation() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rotatedURL = URL(fileURLWithPath: file.path + ".1")
    try Data("stale".utf8).write(to: rotatedURL)
    try Data(repeating: 0x61, count: 10).write(to: file)
    let log = EventLog(file: file, maxBytes: 5)

    log.rotateIfNeeded()

    #expect(!FileManager.default.fileExists(atPath: file.path))
    let rotatedContents = try Data(contentsOf: rotatedURL)
    #expect(rotatedContents.count == 10)

    log.write("fresh")
    #expect(FileManager.default.fileExists(atPath: file.path))
    let freshContents = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    #expect(freshContents.contains("fresh"))
  }
}
