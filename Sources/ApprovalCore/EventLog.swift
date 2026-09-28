import Darwin
import Foundation

public struct EventLog: Sendable {
  let file: URL
  let maxBytes: Int

  public init(file: URL, maxBytes: Int = 1_048_576) {
    self.file = file
    self.maxBytes = maxBytes
  }

  public func rotateIfNeeded() {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
      let size = attributes[.size] as? Int,
      size > maxBytes
    else { return }
    rename(file.path, rotatedPath)
  }

  public func write(_ message: String) {
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
    guard descriptor >= 0 else { return }
    defer { close(descriptor) }
    let line = "\(Self.timestamp()) [\(getpid())] \(message)\n"
    let bytes = Array(line.utf8)
    bytes.withUnsafeBufferPointer { buffer in
      _ = Darwin.write(descriptor, buffer.baseAddress, buffer.count)
    }
  }

  public func redirectStandardError() {
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    var descriptor = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
    if descriptor < 0 {
      descriptor = open("/dev/null", O_WRONLY | O_CLOEXEC)
    }
    guard descriptor >= 0 else { return }
    dup2(descriptor, STDERR_FILENO)
    close(descriptor)
  }

  private var rotatedPath: String {
    file.path + ".1"
  }

  private static func timestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: Date())
  }
}
