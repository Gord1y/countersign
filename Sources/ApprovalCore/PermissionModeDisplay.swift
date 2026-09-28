import Foundation

public struct PermissionModeDisplay: Sendable, Equatable {
  public var label: String
  public var tooltip: String

  public init(label: String, tooltip: String) {
    self.label = label
    self.tooltip = tooltip
  }

  public static func forMode(_ mode: String?, host: Host) -> PermissionModeDisplay? {
    guard let mode else { return nil }
    let trimmed = mode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "default" else { return nil }

    switch trimmed {
    case "plan":
      return PermissionModeDisplay(
        label: "Plan mode",
        tooltip: "Claude is planning and won't change anything until you approve a plan.")
    case "acceptEdits":
      return PermissionModeDisplay(
        label: "Accepting edits",
        tooltip: "File edits in this session are approved automatically. Other tools still ask.")
    case "bypassPermissions":
      return PermissionModeDisplay(
        label: "Bypassing permissions",
        tooltip: "Tools run without asking in this session.")
    case "dontAsk":
      return PermissionModeDisplay(
        label: "Don't ask",
        tooltip: "Tools that aren't already allowed are denied without asking.")
    case "auto":
      return PermissionModeDisplay(
        label: "Auto mode",
        tooltip: "Routine actions are approved automatically. Risky ones still ask.")
    default:
      return PermissionModeDisplay(
        label: trimmed,
        tooltip: "Permission mode reported by \(host.displayName).")
    }
  }
}
