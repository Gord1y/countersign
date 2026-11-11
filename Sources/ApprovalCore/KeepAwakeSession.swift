import Darwin
import Foundation

public struct KeepAwakeSession: Sendable {
  static let foreverWord = "forever"

  let file: URL

  public init(file: URL) {
    self.file = file
  }

  public init(paths: AppPaths) {
    self.init(file: paths.keepAwakeSessionFile)
  }

  public func start(_ end: KeepAwakeEnd) throws {
    let text: String
    switch end {
    case .untilTurnedOff:
      text = Self.foreverWord
    case .at(let date):
      guard let seconds = Int64(exactly: date.timeIntervalSince1970.rounded()) else {
        throw POSIXError(.ERANGE)
      }
      text = String(seconds)
    }
    let directory = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(".\(file.lastPathComponent).tmp")
    try Data(text.utf8).write(to: temporary)
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

  public func current(now: Date = Date()) -> KeepAwakeEnd? {
    guard let data = try? Data(contentsOf: file),
      let text = String(data: data, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
    else { return nil }
    if text == Self.foreverWord { return .untilTurnedOff }
    guard let seconds = Int64(text) else { return nil }
    let end = Date(timeIntervalSince1970: TimeInterval(seconds))
    return end > now ? .at(end) : nil
  }
}
