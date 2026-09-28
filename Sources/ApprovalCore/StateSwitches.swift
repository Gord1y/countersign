import Foundation

public enum SnoozeRefusal: Error, Equatable {
  case paused
}

public struct StateSwitches: Sendable {
  public let pauseSwitch: PauseSwitch
  public let quietTime: QuietTime

  public init(pauseSwitch: PauseSwitch, quietTime: QuietTime) {
    self.pauseSwitch = pauseSwitch
    self.quietTime = quietTime
  }

  public func pause() throws {
    try quietTime.clear()
    try pauseSwitch.pause()
  }

  public func pauseUntilAppOpens() throws -> Bool {
    guard try pauseSwitch.pauseUntilAppOpens() else { return false }
    try quietTime.clear()
    return true
  }

  public func snooze(until: Date) throws {
    guard !pauseSwitch.isPaused else { throw SnoozeRefusal.paused }
    try quietTime.quiet(until: until)
  }
}
