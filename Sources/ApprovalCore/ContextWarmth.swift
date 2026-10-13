import Foundation

public enum ContextCacheLifetime: Sendable, Equatable {
  case fiveMinutes
  case oneHour

  public var seconds: TimeInterval {
    switch self {
    case .fiveMinutes: return 300
    case .oneHour: return 3600
    }
  }
}

public enum ContextWarmth: Sendable, Equatable {
  case warm(secondsLeft: TimeInterval)
  case cold
  case unknown

  public static func of(_ reading: ContextReading, now: Date) -> ContextWarmth {
    guard let lastActivity = reading.lastActivity, let lifetime = reading.cacheLifetime else {
      return .unknown
    }
    let secondsLeft = lastActivity.addingTimeInterval(lifetime.seconds).timeIntervalSince(now)
    return secondsLeft > 0 ? .warm(secondsLeft: secondsLeft) : .cold
  }
}
