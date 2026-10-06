import Darwin
import Foundation

public struct QuietTime: Sendable {
  let file: URL

  public init(file: URL) {
    self.file = file
  }

  public func quiet(until: Date) throws {
    guard let seconds = Int64(exactly: until.timeIntervalSince1970.rounded()) else {
      throw POSIXError(.ERANGE)
    }
    let directory = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = Data(String(seconds).utf8)
    let temporary = directory.appendingPathComponent(".\(file.lastPathComponent).tmp")
    try data.write(to: temporary)
    guard rename(temporary.path, file.path) == 0 else {
      let code = errno
      unlink(temporary.path)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  public func clear() throws {
    do {
      try FileManager.default.removeItem(at: file)
    } catch CocoaError.fileNoSuchFile {
      return
    }
  }

  public func activeUntil(now: Date = Date()) -> Date? {
    guard let data = try? Data(contentsOf: file),
      let text = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      let seconds = Int64(text)
    else { return nil }
    let until = Date(timeIntervalSince1970: TimeInterval(seconds))
    return until > now ? until : nil
  }
}
