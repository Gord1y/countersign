import Foundation

public struct ColdCacheCandidate: Sendable, Equatable {
  public var sessionID: String
  public var project: String
  public var tokens: Int
  public var secondsLeft: TimeInterval
  public var lastActivity: Date

  public init(
    sessionID: String, project: String, tokens: Int, secondsLeft: TimeInterval,
    lastActivity: Date
  ) {
    self.sessionID = sessionID
    self.project = project
    self.tokens = tokens
    self.secondsLeft = secondsLeft
    self.lastActivity = lastActivity
  }
}

public enum ColdCacheWarning {
  public static let leadTime: TimeInterval = 600

  public static func candidates(
    store: ContextCheckpointStore, isIdle: (String) -> Bool,
    settings: ContextCheckpointSettings, now: Date,
    read: (URL) -> ContextReading? = ContextUsageReader.read(transcriptURL:)
  ) -> [ColdCacheCandidate] {
    guard settings.enabled, settings.coldCacheCard else { return [] }
    var candidates: [ColdCacheCandidate] = []
    for sessionID in store.sessionIDs() {
      guard isIdle(sessionID),
        let state = store.load(sessionID: sessionID),
        let transcriptPath = state.transcriptPath,
        let reading = read(URL(fileURLWithPath: transcriptPath)),
        reading.cacheLifetime == .oneHour,
        let lastActivity = reading.lastActivity,
        let gauge = ContextGauge.make(
          reading: reading, state: state, settings: settings, now: now),
        let firstRung = gauge.ladder.first, gauge.tokens >= firstRung,
        case .warm(let secondsLeft) = gauge.warmth,
        secondsLeft > 0, secondsLeft <= leadTime
      else { continue }
      candidates.append(
        ColdCacheCandidate(
          sessionID: sessionID, project: state.project ?? ContextMeter.fallbackProject,
          tokens: gauge.tokens, secondsLeft: secondsLeft, lastActivity: lastActivity))
    }
    candidates.sort { left, right in
      if left.secondsLeft != right.secondsLeft { return left.secondsLeft < right.secondsLeft }
      return left.sessionID < right.sessionID
    }
    return candidates
  }

  public static func isIdle(sessionID: String, sessionsDirectory: URL) -> Bool {
    guard ContextMeter.isLive(sessionID: sessionID, sessionsDirectory: sessionsDirectory),
      let entry = SessionRegistry.findEntry(sessionID: sessionID, in: sessionsDirectory)
    else { return false }
    return entry.fields["status"]?.stringValue == "idle"
  }

  public static func leadText(tokens: Int, secondsLeft: TimeInterval) -> String {
    let size = ContextCheckpointNotes.tokenText(tokens)
    guard secondsLeft >= 60 else { return "\(size) tokens go cold in under a minute · " }
    let minutes = Int((secondsLeft / 60).rounded(.up))
    return "\(size) tokens go cold in \(minutes) min · "
  }
}

public struct ColdCacheWarningLedger: Sendable, Equatable {
  private var warnedActivity: [String: Date] = [:]

  public init() {}

  public func isWarned(_ candidate: ColdCacheCandidate) -> Bool {
    warnedActivity[candidate.sessionID] == candidate.lastActivity
  }

  public mutating func markWarned(_ candidate: ColdCacheCandidate) {
    warnedActivity[candidate.sessionID] = candidate.lastActivity
  }

  public mutating func forget(sessionID: String) {
    warnedActivity[sessionID] = nil
  }
}
