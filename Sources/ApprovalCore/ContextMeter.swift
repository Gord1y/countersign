import Foundation

public struct ContextMeterRow: Sendable, Equatable {
  public var sessionID: String
  public var project: String
  public var tokens: Int
  public var title: String

  public init(sessionID: String, project: String, tokens: Int, title: String) {
    self.sessionID = sessionID
    self.project = project
    self.tokens = tokens
    self.title = title
  }
}

public enum ContextMeter {
  public static let maximumRows = 8
  static let fallbackProject = "Claude Code"

  public static func rows(
    store: ContextCheckpointStore,
    isLive: (String) -> Bool,
    read: (URL) -> ContextReading? = ContextUsageReader.read(transcriptURL:)
  ) -> [ContextMeterRow] {
    var rows: [ContextMeterRow] = []
    for sessionID in store.sessionIDs() {
      guard isLive(sessionID), let state = store.load(sessionID: sessionID) else { continue }
      let freshTokens = state.transcriptPath.flatMap { read(URL(fileURLWithPath: $0)) }?.tokens
      let tokens = freshTokens ?? state.lastTokens
      let project = state.project ?? fallbackProject
      rows.append(
        ContextMeterRow(
          sessionID: sessionID, project: project, tokens: tokens,
          title: "\(project) · \(ContextCheckpointNotes.tokenText(tokens)) tokens"))
    }
    rows.sort { left, right in
      if left.tokens != right.tokens { return left.tokens > right.tokens }
      return left.sessionID < right.sessionID
    }
    return Array(rows.prefix(maximumRows))
  }

  public static func isLive(sessionID: String, sessionsDirectory: URL) -> Bool {
    guard let entry = SessionRegistry.findEntry(sessionID: sessionID, in: sessionsDirectory),
      case .int(let number)? = entry.fields["pid"],
      let pid = Int32(exactly: number)
    else { return false }
    return ProcessLiveness.isAlive(pid: pid, processStart: nil)
  }
}
