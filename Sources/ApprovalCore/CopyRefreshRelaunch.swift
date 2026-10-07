import Darwin
import Foundation

public struct CopyRefreshRelaunch: Equatable, Sendable {
  public let opensSettings: Bool
  public let writtenAt: Date
  public static let freshness: TimeInterval = 120

  public init(opensSettings: Bool, writtenAt: Date) {
    self.opensSettings = opensSettings
    self.writtenAt = writtenAt
  }

  public static func read(_ file: URL) -> CopyRefreshRelaunch? {
    guard let data = try? Data(contentsOf: file),
      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
      case .object(let root) = value,
      case .bool(let opensSettings)? = root["opensSettings"],
      case .int(let seconds)? = root["writtenAt"]
    else { return nil }
    return CopyRefreshRelaunch(
      opensSettings: opensSettings, writtenAt: Date(timeIntervalSince1970: TimeInterval(seconds)))
  }

  public static func write(_ marker: CopyRefreshRelaunch, to file: URL) throws {
    let directory = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(".\(file.lastPathComponent).tmp")
    let root: JSONValue = .object([
      "opensSettings": .bool(marker.opensSettings),
      "writtenAt": .int(Int64(marker.writtenAt.timeIntervalSince1970.rounded(.down))),
    ])
    try JSONEncoder().encode(root).write(to: temporary)
    guard rename(temporary.path, file.path) == 0 else {
      let code = errno
      unlink(temporary.path)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  public func isFresh(now: Date) -> Bool {
    let age = now.timeIntervalSince(writtenAt)
    return age >= 0 && age <= Self.freshness
  }
}
