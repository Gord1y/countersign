import Foundation

public struct NoticeVisibleTime: Sendable, Equatable {
  public static let longestGap: TimeInterval = 5

  public private(set) var seconds: TimeInterval
  private var lastSeen: Date?

  public init() {
    self.seconds = 0
    self.lastSeen = nil
  }

  public mutating func advance(to now: Date, counting: Bool) {
    if counting, let lastSeen {
      let gap = now.timeIntervalSince(lastSeen)
      seconds += min(max(gap, 0), Self.longestGap)
    }
    lastSeen = now
  }
}
