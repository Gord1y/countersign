import AppKit
import ApprovalCore

@MainActor
enum WaitingHookPrompt {
  static let cancelTitle = "Cancel"
  static let okTitle = "OK"
  static let nothingToChange = "Nothing to change."

  static func message(for change: WaitingHookChange) -> String {
    change.enable ? "Turn on waiting-agent notices?" : "Turn off waiting-agent notices?"
  }

  static func informativeText(for change: WaitingHookChange, home: URL) -> String {
    guard change.canApply, change.preview.hasChanges else { return "" }
    let paths = change.preview.changedFiles
      .map { HomePath.abbreviating($0.path, relativeTo: home) }
      .joined(separator: ", ")
    return "Countersign changes \(paths) and keeps a backup."
  }

  static func makeAlert(change: WaitingHookChange, home: URL) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message(for: change)
    alert.informativeText = informativeText(for: change, home: home)
    alert.accessoryView = HookDiffPreview.view(text: previewText(for: change))
    if change.canApply {
      alert.addButton(withTitle: change.confirmTitle)
      alert.addButton(withTitle: cancelTitle)
    } else {
      alert.addButton(withTitle: okTitle)
    }
    return alert
  }

  static func present(
    change: WaitingHookChange, home: URL, on window: NSWindow?,
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

  private static func previewText(for change: WaitingHookChange) -> String {
    guard change.canApply else { return change.preview.failures.joined(separator: "\n") }
    return change.preview.text.isEmpty ? nothingToChange : change.preview.text
  }
}
