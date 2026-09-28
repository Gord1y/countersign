import Foundation

public enum PauseState: Sendable, Equatable {
  case active
  case paused
  case pausedUntilAppOpens

  public var description: String {
    switch self {
    case .active: return "active"
    case .paused: return "paused"
    case .pausedUntilAppOpens: return "paused until Countersign opens"
    }
  }
}

public struct PauseSwitch: Sendable {
  static let untilAppOpensMarker = Data("until Countersign opens\n".utf8)

  let file: URL

  public init(file: URL) {
    self.file = file
  }

  public var isPaused: Bool {
    FileManager.default.fileExists(atPath: file.path)
  }

  public var state: PauseState {
    guard isPaused else { return .active }
    guard FileManager.default.contents(atPath: file.path) == Self.untilAppOpensMarker else {
      return .paused
    }
    return .pausedUntilAppOpens
  }

  public func pause() throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: file)
  }

  public func pauseUntilAppOpens() throws -> Bool {
    guard state != .paused else { return false }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.untilAppOpensMarker.write(to: file, options: .atomic)
    return true
  }

  public func resume() throws {
    do {
      try FileManager.default.removeItem(at: file)
    } catch CocoaError.fileNoSuchFile {
      return
    }
  }

  public func resumeIfPausedUntilAppOpens() throws -> Bool {
    guard state == .pausedUntilAppOpens else { return false }
    try resume()
    return true
  }
}
