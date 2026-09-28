import Darwin
import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ExclusiveFileLockTests {
  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-lock-\(UUID().uuidString)")
  }

  @Test func aSecondAcquisitionFailsWhileTheFirstIsHeldAndSucceedsAfterRelease() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("companion.lock")

    let first = try #require(try ExclusiveFileLock.acquire(file))
    #expect(try ExclusiveFileLock.acquire(file) == nil)
    #expect(try ExclusiveFileLock.acquire(file) == nil)
    first.release()

    let second = try #require(try ExclusiveFileLock.acquire(file))
    second.release()
  }

  @Test func droppingTheLastReferenceReleasesTheLock() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("companion.lock")

    func acquireThenDrop() throws -> Bool {
      let lock = try ExclusiveFileLock.acquire(file)
      return try withExtendedLifetime(lock) {
        try lock != nil && ExclusiveFileLock.acquire(file) == nil
      }
    }

    #expect(try acquireThenDrop())
    let again = try #require(try ExclusiveFileLock.acquire(file))
    again.release()
  }

  @Test func releaseIsIdempotent() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("companion.lock")

    let first = try #require(try ExclusiveFileLock.acquire(file))
    first.release()
    let second = try #require(try ExclusiveFileLock.acquire(file))
    first.release()
    #expect(try ExclusiveFileLock.acquire(file) == nil)
    second.release()
  }

  @Test func createsMissingDirectoriesAndNeverDeletesTheLockFile() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppPaths(home: root)

    let lock = try #require(try ExclusiveFileLock.acquire(paths.companionLockFile))
    #expect(FileManager.default.fileExists(atPath: paths.companionLockFile.path))
    lock.release()
    #expect(FileManager.default.fileExists(atPath: paths.companionLockFile.path))
  }

  @Test func throwsWhenTheLockFileCannotBeOpened() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let blocker = root.appendingPathComponent("not-a-directory")
    try Data("x".utf8).write(to: blocker)

    #expect(throws: POSIXError.self) {
      try ExclusiveFileLock.acquire(blocker.appendingPathComponent("companion.lock"))
    }
  }

  @Test func descriptorIsNotInheritedBySpawnedChildren() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("companion.lock")
    let lockSuffix = "\(root.lastPathComponent)/companion.lock"
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let inheritable = open(file.path, O_RDWR | O_CREAT, 0o644)
    try #require(inheritable >= 0)
    let witness = try ChildProcess.spawnInheritingDescriptors("/bin/sleep", ["30"])
    let witnessPaths = ChildProcess.openVnodePaths(of: witness)
    ChildProcess.reap(witness)
    close(inheritable)
    #expect(witnessPaths.contains { $0.hasSuffix(lockSuffix) })

    let lock = try #require(try ExclusiveFileLock.acquire(file))
    let child = try ChildProcess.spawnInheritingDescriptors("/bin/sleep", ["30"])
    let childPaths = ChildProcess.openVnodePaths(of: child)
    ChildProcess.reap(child)
    lock.release()

    #expect(!childPaths.contains { $0.hasSuffix(lockSuffix) })
  }
}
