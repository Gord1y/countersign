import Foundation
import Testing

@testable import ApprovalCore

@Suite struct QuietTimeTests {
  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-quiettime-\(UUID().uuidString)")
      .appendingPathComponent("nested")
      .appendingPathComponent("quiet-until")
  }

  private func removeContainer(of file: URL) {
    let container = file.deletingLastPathComponent().deletingLastPathComponent()
    try? FileManager.default.removeItem(at: container)
  }

  @Test func activeUntilIsNilWhenTheFileIsMissing() {
    let file = temporaryFile()
    let quietTime = QuietTime(file: file)

    #expect(quietTime.activeUntil() == nil)
  }

  @Test func quietCreatesTheDirectoryAndWritesEpochSeconds() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let quietTime = QuietTime(file: file)
    let until = Date().addingTimeInterval(300)

    try quietTime.quiet(until: until)

    let contents = String(decoding: try Data(contentsOf: file), as: UTF8.self)
    #expect(Int64(contents) == Int64(until.timeIntervalSince1970.rounded()))
  }

  @Test func activeUntilReturnsTheStoredDateWhenInTheFuture() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let quietTime = QuietTime(file: file)
    let until = Date().addingTimeInterval(120)

    try quietTime.quiet(until: until)

    let active = quietTime.activeUntil()
    #expect(active != nil)
    #expect(abs((active ?? .distantPast).timeIntervalSince(until)) < 1)
  }

  @Test func activeUntilIsNilWhenTheStoredDateIsInThePast() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let quietTime = QuietTime(file: file)
    let until = Date().addingTimeInterval(-60)

    try quietTime.quiet(until: until)

    #expect(quietTime.activeUntil() == nil)
  }

  @Test func activeUntilIsNilWhenTheFileIsUnparseable() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not a number".utf8).write(to: file)
    let quietTime = QuietTime(file: file)

    #expect(quietTime.activeUntil() == nil)
  }

  @Test func clearRemovesTheFile() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let quietTime = QuietTime(file: file)
    try quietTime.quiet(until: Date().addingTimeInterval(60))

    try quietTime.clear()

    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func clearToleratesAMissingFile() {
    let file = temporaryFile()
    let quietTime = QuietTime(file: file)

    #expect(throws: Never.self) {
      try quietTime.clear()
    }
  }

  @Test func quietOverwritesAPreviousValue() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let quietTime = QuietTime(file: file)
    try quietTime.quiet(until: Date().addingTimeInterval(60))

    let laterUntil = Date().addingTimeInterval(900)
    try quietTime.quiet(until: laterUntil)

    let active = quietTime.activeUntil()
    #expect(active != nil)
    #expect(abs((active ?? .distantPast).timeIntervalSince(laterUntil)) < 1)
  }
}
