import Foundation
import Testing

@testable import ApprovalCore

@Suite struct CompanionProbeTests {
  private func temporaryPaths() -> (AppPaths, URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-probe-\(UUID().uuidString)")
    return (AppPaths(home: root), root)
  }

  @Test func reportsNotRunningWithoutALockFile() {
    let (paths, root) = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(!CompanionProbe.isRunning(paths: paths))
  }

  @Test func reportsRunningWhileTheLockIsHeld() throws {
    let (paths, root) = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: root) }
    let held = try #require(try ExclusiveFileLock.acquire(paths.companionLockFile))
    defer { held.release() }
    #expect(CompanionProbe.isRunning(paths: paths))
  }

  @Test func leavesTheLockAcquirableAfterReportingNotRunning() throws {
    let (paths, root) = temporaryPaths()
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(!CompanionProbe.isRunning(paths: paths))
    let lock = try #require(try ExclusiveFileLock.acquire(paths.companionLockFile))
    lock.release()
  }
}
