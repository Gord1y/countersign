import Foundation
import Testing

@testable import ApprovalCore

@Suite struct CopyRefreshRelaunchTests {
  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-relaunch-after-copy-\(UUID().uuidString)")
      .appendingPathComponent("nested")
      .appendingPathComponent("relaunch-after-copy")
  }

  private func removeContainer(of file: URL) {
    let container = file.deletingLastPathComponent().deletingLastPathComponent()
    try? FileManager.default.removeItem(at: container)
  }

  @Test(arguments: [true, false])
  func writeThenReadRoundTripsOpensSettings(_ opensSettings: Bool) throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let marker = CopyRefreshRelaunch(
      opensSettings: opensSettings, writtenAt: Date(timeIntervalSince1970: 1_700_000_000))

    try CopyRefreshRelaunch.write(marker, to: file)

    #expect(CopyRefreshRelaunch.read(file) == marker)
  }

  @Test func isFreshOnlyWithinTheFreshnessWindowAndNeverInTheFuture() {
    let writtenAt = Date(timeIntervalSince1970: 1_700_000_000)
    let marker = CopyRefreshRelaunch(opensSettings: true, writtenAt: writtenAt)

    #expect(marker.isFresh(now: writtenAt.addingTimeInterval(30)))
    #expect(!marker.isFresh(now: writtenAt.addingTimeInterval(300)))
    #expect(!marker.isFresh(now: writtenAt.addingTimeInterval(-60)))
  }

  @Test func readReturnsNilForAMissingFileAndForAFileThatIsNotJSON() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }

    #expect(CopyRefreshRelaunch.read(file) == nil)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: file)

    #expect(CopyRefreshRelaunch.read(file) == nil)
  }

  @Test func theMarkerFileSitsNextToTheTourShownFile() {
    let paths = AppPaths(home: URL(fileURLWithPath: "/Users/dev"))

    #expect(
      paths.copyRefreshRelaunchFile.deletingLastPathComponent()
        == paths.tourShownFile.deletingLastPathComponent())
    #expect(paths.copyRefreshRelaunchFile.lastPathComponent == "relaunch-after-copy")
  }
}
