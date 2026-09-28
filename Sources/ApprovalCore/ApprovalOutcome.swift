import Foundation

public enum ApprovalOutcome: Sendable, Equatable {
  case allow(updatedInput: JSONValue?, updatedPermissions: [JSONValue])
  case deny(message: String, interrupt: Bool)
  case noDecision

  public static let allowAsIs = ApprovalOutcome.allow(updatedInput: nil, updatedPermissions: [])

  public static let defaultDenyMessage = "Denied in the approval panel."

  public static func deny(reason: String, interrupt: Bool) -> ApprovalOutcome {
    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    let message = trimmed.isEmpty ? defaultDenyMessage : trimmed
    return .deny(message: message, interrupt: interrupt)
  }
}
