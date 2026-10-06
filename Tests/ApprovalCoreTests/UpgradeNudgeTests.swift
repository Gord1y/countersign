import Foundation
import Testing

@testable import ApprovalCore

@Suite struct UpgradeNudgeTests {
  @Test func isUpgradeComparesLastSeenVersionOrFallsBackToTheTour() {
    #expect(UpgradeNudge.isUpgrade(lastSeenVersion: nil, tourShown: true, currentVersion: "0.2.0"))
    #expect(
      !UpgradeNudge.isUpgrade(lastSeenVersion: nil, tourShown: false, currentVersion: "0.2.0"))
    #expect(
      !UpgradeNudge.isUpgrade(lastSeenVersion: "0.2.0", tourShown: true, currentVersion: "0.2.0"))
    #expect(
      UpgradeNudge.isUpgrade(lastSeenVersion: "0.1.0", tourShown: false, currentVersion: "0.2.0"))
  }

  @Test func onlyNeedsUpdateCountsAsNeedingAnAgentUpdate() {
    let update = HostWiringStatus.needsUpdate(HostWiringUpdate(otherExecutablePaths: []))
    #expect(!UpgradeNudge.needsAgentUpdate([.wired, .notInstalled, .notWired]))
    #expect(UpgradeNudge.needsAgentUpdate([.wired, update, .notInstalled, .notWired]))
    #expect(!UpgradeNudge.needsAgentUpdate([.unusable("x")]))
  }

  @Test func recordsAndReadsTheLastSeenVersion() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("upgrade-nudge-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("nested").appendingPathComponent(
      "last-seen-version")
    #expect(UpgradeNudge.readLastSeenVersion(file: file) == nil)
    try UpgradeNudge.recordVersion("0.2.0", file: file)
    #expect(UpgradeNudge.readLastSeenVersion(file: file) == "0.2.0")
    try Data("  \n".utf8).write(to: file)
    #expect(UpgradeNudge.readLastSeenVersion(file: file) == nil)
    try Data(" 0.1.0\n".utf8).write(to: file)
    #expect(UpgradeNudge.readLastSeenVersion(file: file) == "0.1.0")
  }
}
