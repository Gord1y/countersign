import Foundation

public enum ContextWindow {
  public static let disableMillionVariable = "CLAUDE_CODE_DISABLE_1M_CONTEXT"

  public static func isMillionDisabled(environment: [String: String]) -> Bool {
    guard let value = environment[disableMillionVariable] else { return false }
    return ["1", "true", "yes"].contains(
      value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
  }

  public static func hasMillionTokens(modelID: String?, tokens: Int, millionDisabled: Bool) -> Bool
  {
    if tokens > ContextUsageReader.standardWindowTokens { return true }
    if millionDisabled { return false }
    guard let modelID else { return false }
    if modelID.contains(ContextUsageReader.millionTokenMarker) { return true }
    return !predatesDefaultMillion(modelID)
  }

  private static func predatesDefaultMillion(_ modelID: String) -> Bool {
    let legacy = /claude-(\d|instant)/
    if modelID.firstMatch(of: legacy) != nil { return true }
    let current = /claude-(opus|sonnet|haiku)-(\d+)(?:-(\d{1,2}))?(?!\d)/
    guard let match = modelID.firstMatch(of: current), let major = Int(match.2) else {
      return false
    }
    if major != 4 { return major < 4 }
    if match.1 != "opus" { return true }
    guard let minorText = match.3, let minor = Int(minorText) else { return true }
    return minor <= 6
  }
}
