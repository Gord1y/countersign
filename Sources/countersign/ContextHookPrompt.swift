import AppKit
import ApprovalCore

@MainActor
enum ContextHookPrompt {
  static let cancelTitle = "Cancel"
  static let okTitle = "OK"

  static func message(for change: ContextHookChange) -> String {
    guard change.origin == .toggle else { return "Update Countersign's Claude Code hook?" }
    return change.enable ? "Turn on context checkpoints?" : "Turn off context checkpoints?"
  }

  static func informativeText(for change: ContextHookChange, path: String) -> String {
    change.canApply ? "Countersign changes \(path) and keeps a backup." : ""
  }

  static func makeAlert(change: ContextHookChange, path: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message(for: change)
    alert.informativeText = informativeText(for: change, path: path)
    alert.accessoryView = HookDiffDisclosure.accessoryView(
      for: alert, text: change.canApply ? change.preview.text : failureText(change),
      isDiff: change.canApply && change.preview.hasChanges)
    if change.canApply {
      alert.addButton(withTitle: change.confirmTitle)
      alert.addButton(withTitle: cancelTitle)
    } else {
      alert.addButton(withTitle: okTitle)
    }
    return alert
  }

  static func present(
    change: ContextHookChange, path: String, on window: NSWindow?,
    onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void
  ) {
    let alert = makeAlert(change: change, path: path)
    let canApply = change.canApply
    guard let window else {
      handle(alert.runModal(), canApply: canApply, onConfirm: onConfirm, onCancel: onCancel)
      return
    }
    alert.beginSheetModal(for: window) { response in
      handle(response, canApply: canApply, onConfirm: onConfirm, onCancel: onCancel)
    }
  }

  private static func handle(
    _ response: NSApplication.ModalResponse, canApply: Bool, onConfirm: () -> Void,
    onCancel: () -> Void
  ) {
    if canApply, response == .alertFirstButtonReturn {
      onConfirm()
    } else {
      onCancel()
    }
  }

  private static func failureText(_ change: ContextHookChange) -> String {
    change.preview.failures.joined(separator: "\n")
  }
}
