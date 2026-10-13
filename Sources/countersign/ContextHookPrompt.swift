import AppKit
import ApprovalCore

@MainActor
enum ContextHookPrompt {
  static let cancelTitle = "Cancel"
  static let okTitle = "OK"

  static let codexTrustSentence =
    " Codex then asks you to trust the new hooks: run /hooks in a Codex session."

  static func message(for change: ContextHookChange) -> String {
    switch change.origin {
    case .hookStatus: return "Update Countersign's Claude Code hooks?"
    case .codexHookStatus: return "Update Countersign's Codex hooks?"
    case .toggle:
      return change.enable ? "Turn on context checkpoints?" : "Turn off context checkpoints?"
    }
  }

  static func informativeText(for change: ContextHookChange, home: URL) -> String {
    guard change.canApply else { return "" }
    let paths = change.preview.changedFiles
      .map { HomePath.abbreviating($0.path, relativeTo: home) }
      .joined(separator: ", ")
    guard !paths.isEmpty else { return "" }
    let base = "Countersign changes \(paths) and keeps a backup."
    return change.asksCodexTrust ? base + codexTrustSentence : base
  }

  static func makeAlert(change: ContextHookChange, home: URL) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message(for: change)
    alert.informativeText = informativeText(for: change, home: home)
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
    change: ContextHookChange, home: URL, on window: NSWindow?,
    onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void
  ) {
    let alert = makeAlert(change: change, home: home)
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
