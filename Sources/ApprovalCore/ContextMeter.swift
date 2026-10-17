import Foundation

public struct ContextMeterRow: Sendable, Equatable {
  public var sessionID: String
  public var project: String
  public var tokens: Int
  public var windowPercent: Int
  public var warmth: ContextWarmth
  public var title: String

  public init(
    sessionID: String, project: String, tokens: Int, windowPercent: Int, warmth: ContextWarmth,
    title: String
  ) {
    self.sessionID = sessionID
    self.project = project
    self.tokens = tokens
    self.windowPercent = windowPercent
    self.warmth = warmth
    self.title = title
  }
}

public enum ContextMeter {
  public static let maximumRows = 8
  static let fallbackProject = "Claude Code"

  public static func rows(
    store: ContextCheckpointStore,
    isLive: (String) -> Bool,
    settings: ContextCheckpointSettings = .default,
    now: Date = Date(),
    read: (URL) -> ContextReading? = { ContextUsageReader.read(transcriptURL: $0) }
  ) -> [ContextMeterRow] {
    var rows: [ContextMeterRow] = []
    for sessionID in store.sessionIDs() {
      guard isLive(sessionID), let state = store.load(sessionID: sessionID) else { continue }
      let freshReading = state.transcriptPath.flatMap { read(URL(fileURLWithPath: $0)) }
      guard
        let gauge = ContextGauge.make(
          reading: freshReading, state: state, settings: settings, now: now)
      else { continue }
      let project = state.project ?? fallbackProject
      let sizeText = "\(project) · \(ContextCheckpointNotes.tokenText(gauge.tokens)) tokens"
      rows.append(
        ContextMeterRow(
          sessionID: sessionID, project: project, tokens: gauge.tokens,
          windowPercent: gauge.windowPercent, warmth: gauge.warmth,
          title: "\(sizeText) · \(gauge.windowPercent)%\(warmthSuffix(gauge.warmth))"))
    }
    rows.sort { left, right in
      if left.tokens != right.tokens { return left.tokens > right.tokens }
      return left.sessionID < right.sessionID
    }
    return Array(rows.prefix(maximumRows))
  }

  private static func warmthSuffix(_ warmth: ContextWarmth) -> String {
    warmth.phrase.map { " · \($0)" } ?? ""
  }

  public static func isLive(sessionID: String, sessionsDirectory: URL) -> Bool {
    guard let entry = SessionRegistry.findEntry(sessionID: sessionID, in: sessionsDirectory),
      case .int(let number)? = entry.fields["pid"],
      let pid = Int32(exactly: number)
    else { return false }
    return ProcessLiveness.isAlive(pid: pid, processStart: nil)
  }
}
