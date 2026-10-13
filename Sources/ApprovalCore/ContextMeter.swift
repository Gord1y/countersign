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
    now: Date = Date(),
    read: (URL) -> ContextReading? = ContextUsageReader.read(transcriptURL:)
  ) -> [ContextMeterRow] {
    var rows: [ContextMeterRow] = []
    for sessionID in store.sessionIDs() {
      guard isLive(sessionID), let state = store.load(sessionID: sessionID) else { continue }
      let freshReading = state.transcriptPath.flatMap { read(URL(fileURLWithPath: $0)) }
      let tokens = freshReading?.tokens ?? state.lastTokens
      let project = state.project ?? fallbackProject
      let hasMillionWindow =
        freshReading?.hasMillionTokenWindow == true
        || state.modelID?.contains(ContextUsageReader.millionTokenMarker) == true
        || tokens > ContextUsageReader.standardWindowTokens
      let window =
        hasMillionWindow
        ? ContextUsageReader.millionWindowTokens : ContextUsageReader.standardWindowTokens
      let windowPercent = Int((Double(tokens) * 100 / Double(window)).rounded())
      let warmth = freshReading.map { ContextWarmth.of($0, now: now) } ?? .unknown
      let sizeText = "\(project) · \(ContextCheckpointNotes.tokenText(tokens)) tokens"
      rows.append(
        ContextMeterRow(
          sessionID: sessionID, project: project, tokens: tokens, windowPercent: windowPercent,
          warmth: warmth,
          title: "\(sizeText) · \(windowPercent)%\(warmthSuffix(warmth))"))
    }
    rows.sort { left, right in
      if left.tokens != right.tokens { return left.tokens > right.tokens }
      return left.sessionID < right.sessionID
    }
    return Array(rows.prefix(maximumRows))
  }

  private static func warmthSuffix(_ warmth: ContextWarmth) -> String {
    switch warmth {
    case .unknown:
      return ""
    case .cold:
      return " · cold"
    case .warm(let secondsLeft):
      if secondsLeft < 60 { return " · warm, under a minute left" }
      return " · warm, \(Int((secondsLeft / 60).rounded(.up))) min left"
    }
  }

  public static func isLive(sessionID: String, sessionsDirectory: URL) -> Bool {
    guard let entry = SessionRegistry.findEntry(sessionID: sessionID, in: sessionsDirectory),
      case .int(let number)? = entry.fields["pid"],
      let pid = Int32(exactly: number)
    else { return false }
    return ProcessLiveness.isAlive(pid: pid, processStart: nil)
  }
}
