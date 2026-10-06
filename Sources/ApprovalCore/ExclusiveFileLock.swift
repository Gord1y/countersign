import Darwin
import Foundation
import os

public final class ExclusiveFileLock: Sendable {
  private let descriptor: OSAllocatedUnfairLock<Int32?>

  private init(descriptor: Int32) {
    self.descriptor = OSAllocatedUnfairLock(initialState: descriptor)
  }

  public static func acquire(_ file: URL) throws -> ExclusiveFileLock? {
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let fileDescriptor = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
    guard fileDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(fileDescriptor)
      return nil
    }
    guard isStillLinked(fileDescriptor, at: file) else {
      flock(fileDescriptor, LOCK_UN)
      close(fileDescriptor)
      return nil
    }
    return ExclusiveFileLock(descriptor: fileDescriptor)
  }

  static func isStillLinked(_ descriptor: Int32, at file: URL) -> Bool {
    var opened = stat()
    var current = stat()
    guard fstat(descriptor, &opened) == 0, stat(file.path, &current) == 0 else { return false }
    return opened.st_dev == current.st_dev && opened.st_ino == current.st_ino
  }

  public func removeFile(_ file: URL) {
    descriptor.withLock { current in
      guard current != nil else { return }
      unlink(file.path)
    }
  }

  public func release() {
    let taken = descriptor.withLock { current -> Int32? in
      let taken = current
      current = nil
      return taken
    }
    guard let taken else { return }
    flock(taken, LOCK_UN)
    close(taken)
  }

  deinit {
    release()
  }
}
