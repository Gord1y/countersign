import Foundation

public enum UpdateCheckOutcome: Sendable, Equatable {
  case newerAvailable(version: String)
  case upToDate
  case unknown(reason: String)
}

public enum UpdateCheck {
  public static func evaluate(indexData: Data, currentVersion: String) -> UpdateCheckOutcome {
    switch ReleaseIndex.latestVersion(from: indexData) {
    case .success(let version):
      guard let version else { return .upToDate }
      return compare(current: currentVersion, latest: version)
    case .failure(let error):
      return .unknown(reason: error.reason)
    }
  }

  static func compare(current: String, latest: String) -> UpdateCheckOutcome {
    guard let currentParts = semverParts(current), let latestParts = semverParts(latest) else {
      return .unknown(reason: "could not compare versions")
    }
    if currentParts.lexicographicallyPrecedes(latestParts) {
      return .newerAvailable(version: latest)
    }
    return .upToDate
  }

  static func semverParts(_ value: String) -> [Int]? {
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var result: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let intValue = Int(part)
      else {
        return nil
      }
      result.append(intValue)
    }
    return result
  }
}

public enum UpdateCheckSchedule {
  public static let interval: TimeInterval = 24 * 60 * 60

  public static func isDue(lastAttempt: Date?, now: Date) -> Bool {
    guard let lastAttempt else { return true }
    let elapsed = now.timeIntervalSince(lastAttempt)
    return elapsed < 0 || elapsed >= interval
  }
}
