import Foundation

public struct WaitingEnvelope: Sendable, Equatable {
  public let sessionID: String
  public let projectPath: String
  public let transcriptPath: String?

  public var projectName: String {
    ApprovalRequest.projectName(cwd: projectPath)
  }

  public static func parse(_ data: Data, host: Host) -> WaitingEnvelope? {
    guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
      case .object(let root) = decoded
    else { return nil }
    let sessionID: String?
    let projectPath: String?
    let transcriptPath: String?
    switch host {
    case .claude, .codex:
      sessionID = text(root["session_id"])
      projectPath = text(root["cwd"])
      transcriptPath = text(root["transcript_path"])
    case .cursor:
      sessionID = text(root["conversation_id"]) ?? text(root["session_id"])
      projectPath = text(root["workspace_roots"]?.arrayValue?.first) ?? text(root["cwd"])
      transcriptPath = text(root["transcript_path"])
    case .antigravity:
      sessionID = text(root["conversationId"])
      projectPath = text(root["workspacePaths"]?.arrayValue?.first)
      transcriptPath = text(root["transcriptPath"])
    }
    guard let sessionID, let projectPath else { return nil }
    return WaitingEnvelope(
      sessionID: sessionID, projectPath: projectPath, transcriptPath: transcriptPath)
  }

  private static func text(_ value: JSONValue?) -> String? {
    guard let string = value?.stringValue, !string.isEmpty else { return nil }
    return string
  }
}
