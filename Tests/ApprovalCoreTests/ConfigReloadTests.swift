import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ConfigReloadTests {
  private func temporaryPaths() -> AppPaths {
    AppPaths(
      home: FileManager.default.temporaryDirectory
        .appendingPathComponent("countersign-reload-\(UUID().uuidString)"))
  }

  private func write(_ json: String, to paths: AppPaths) throws {
    try FileManager.default.createDirectory(
      at: paths.configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(json.utf8).write(to: paths.configFile)
  }

  private func reload(_ paths: AppPaths) -> ConfigReload {
    ConfigReload(paths: paths, soundNames: [])
  }

  @Test func theFirstCallRecordsAndReturnsNothing() throws {
    let paths = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.home) }
    try write(#"{"waitingNotices": false}"#, to: paths)
    var watch = reload(paths)

    #expect(watch.changedFile() == nil)
  }

  @Test func unchangedBytesReturnNothing() throws {
    let paths = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.home) }
    try write(#"{"waitingNotices": false}"#, to: paths)
    var watch = reload(paths)
    _ = watch.changedFile()

    #expect(watch.changedFile() == nil)
    #expect(watch.changedFile() == nil)
  }

  @Test func changedBytesReturnTheNewFile() throws {
    let paths = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.home) }
    try write(#"{"waitingNotices": true}"#, to: paths)
    var watch = reload(paths)
    _ = watch.changedFile()

    try write(#"{"waitingNotices": false}"#, to: paths)

    let fileCandidate = watch.changedFile()
    let file = try #require(fileCandidate)
    #expect(Settings.resolve(file: file, host: .claude).waitingNotices == false)
    #expect(watch.changedFile() == nil)
  }

  @Test func deletingTheFileReturnsTheDefaults() throws {
    let paths = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.home) }
    try write(#"{"waitingNotices": false}"#, to: paths)
    var watch = reload(paths)
    _ = watch.changedFile()

    try FileManager.default.removeItem(at: paths.configFile)

    let fileCandidate = watch.changedFile()
    let file = try #require(fileCandidate)
    #expect(file == ConfigFile())
    #expect(Settings.resolve(file: file, host: .claude).waitingNotices)
  }

  @Test func aMissingFileAtStartIsItsOwnState() throws {
    let paths = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.home) }
    var watch = reload(paths)
    #expect(watch.changedFile() == nil)
    #expect(watch.changedFile() == nil)

    try write(#"{"waitingNotices": false}"#, to: paths)

    #expect(watch.changedFile() != nil)
  }

  @Test func twoQuickRewritesAreBothSeen() throws {
    let paths = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.home) }
    try write(#"{"waitingNotices": true}"#, to: paths)
    var watch = reload(paths)
    _ = watch.changedFile()

    try write(#"{"waitingNotices": false}"#, to: paths)
    let firstCandidate = watch.changedFile()
    let first = try #require(firstCandidate)
    try write(#"{"waitingNotices":  true}"#, to: paths)
    let secondCandidate = watch.changedFile()
    let second = try #require(secondCandidate)

    #expect(Settings.resolve(file: first, host: .claude).waitingNotices == false)
    #expect(Settings.resolve(file: second, host: .claude).waitingNotices)
  }
}
