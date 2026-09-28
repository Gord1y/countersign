import Foundation

public enum PlanApprovalMode: String, CaseIterable, Sendable {
  case `default`
  case acceptEdits
  case auto

  public var title: String {
    switch self {
    case .default: return "Ask before edits"
    case .acceptEdits: return "Accept edits"
    case .auto: return "Auto"
    }
  }
}

public enum PlanResponse {
  public static let defaultFeedback = "Not approved yet. Keep planning."

  public static func approve(toolInput: JSONValue, mode: PlanApprovalMode) -> ApprovalOutcome {
    .allow(
      updatedInput: toolInput,
      updatedPermissions: [
        .object([
          "type": .string("setMode"),
          "mode": .string(mode.rawValue),
          "destination": .string("session"),
        ])
      ]
    )
  }

  public static func keepPlanning(feedback: String) -> ApprovalOutcome {
    let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    let message = trimmed.isEmpty ? defaultFeedback : trimmed
    return .deny(message: message, interrupt: false)
  }
}
