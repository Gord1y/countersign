import Foundation

public enum ChatTrackingDrift: Sendable, Equatable {
  case noRegistryEntry
  case unknownStatus(String?)
  case transcriptUnreadable

  public var reason: String {
    switch self {
    case .noRegistryEntry:
      return "no registry entry"
    case .unknownStatus(let status):
      guard let status else {
        return "no status"
      }
      return "unexpected status \(status)"
    case .transcriptUnreadable:
      return "transcript unreadable"
    }
  }
}

public enum ChatTrackingHealth {
  private static let knownStatuses: Set<String> = ["idle", "busy", "waiting"]

  public static func evaluate(
    request: ApprovalRequest,
    sessionsDirectory: URL
  ) -> ChatTrackingDrift? {
    guard request.host == .claude else {
      return nil
    }
    if let drift = evaluateRegistry(
      sessionID: request.sessionID, sessionsDirectory: sessionsDirectory)
    {
      return drift
    }
    return evaluateTranscript(request: request)
  }

  public static func evaluateRegistry(
    sessionID: String,
    sessionsDirectory: URL
  ) -> ChatTrackingDrift? {
    guard let entry = SessionRegistry.findEntry(sessionID: sessionID, in: sessionsDirectory) else {
      return .noRegistryEntry
    }
    guard let status = entry.fields["status"]?.stringValue, knownStatuses.contains(status) else {
      return .unknownStatus(entry.fields["status"]?.stringValue)
    }
    return nil
  }

  public static func evaluateTranscript(request: ApprovalRequest) -> ChatTrackingDrift? {
    guard request.host == .claude else {
      return nil
    }
    guard let transcriptURL = ResolutionWatcher.resolveTranscriptURL(for: request),
      isReadable(transcriptURL)
    else {
      return .transcriptUnreadable
    }
    return nil
  }

  private static func isReadable(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return false
    }
    try? handle.close()
    return true
  }
}
