public struct PermissionSuggestionText: Sendable, Equatable {
  public let title: String
  public let detail: String?

  public init(_ suggestion: PermissionSuggestion) {
    let entry = suggestion.raw
    switch entry["type"]?.stringValue {
    case "addRules":
      let rules = entry["rules"]?.arrayValue ?? []
      title = rules.compactMap(Self.ruleTitle).joined(separator: ", ")
      detail = Self.destinationText(entry["destination"]?.stringValue)
    case "addDirectories":
      let directories = entry["directories"]?.arrayValue?.compactMap(\.stringValue) ?? []
      title = "Allow access to \(directories.joined(separator: ", "))"
      detail = Self.destinationText(entry["destination"]?.stringValue)
    default:
      title = suggestion.label
      detail = nil
    }
  }

  private static func ruleTitle(_ rule: JSONValue) -> String? {
    guard let toolName = rule["toolName"]?.stringValue else { return nil }
    guard let ruleContent = rule["ruleContent"]?.stringValue, !ruleContent.isEmpty else {
      return toolName
    }
    return "\(toolName)(\(ruleContent))"
  }

  private static func destinationText(_ destination: String?) -> String? {
    switch destination {
    case "localSettings": return "This project, on this Mac"
    case "projectSettings": return "This project, shared"
    case "userSettings": return "All projects"
    case "session": return "This session"
    default: return nil
    }
  }
}
