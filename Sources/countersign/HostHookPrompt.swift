import AppKit
import ApprovalCore

@MainActor
enum HostHookPrompt {
  static let cancelTitle = "Cancel"
  static let okTitle = "OK"
  static let nothingToChange = "Nothing to change."

  static func message(for change: HostHookChange) -> String {
    let agent = change.host.displayName
    switch change.action {
    case .wire: return "Wire \(agent) to Countersign?"
    case .update: return "Update Countersign's \(agent) hook?"
    case .remove: return "Remove Countersign's \(agent) hook?"
    }
  }

  static func informativeText(for change: HostHookChange, home: URL) -> String {
    guard change.canApply, change.preview.hasChanges else { return "" }
    let paths = change.preview.changedFiles
      .map { HomePath.abbreviating($0.path, relativeTo: home) }
      .joined(separator: ", ")
    guard !change.createsFile else { return "Countersign creates \(paths)." }
    return "Countersign changes \(paths) and keeps a backup."
  }

  static func makeAlert(change: HostHookChange, home: URL) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message(for: change)
    alert.informativeText = informativeText(for: change, home: home)
    alert.accessoryView = HookDiffPreview.view(text: previewText(for: change))
    if change.canApply {
      alert.addButton(withTitle: change.action.title)
      alert.addButton(withTitle: cancelTitle)
    } else {
      alert.addButton(withTitle: okTitle)
    }
    return alert
  }

  static func present(
    change: HostHookChange, home: URL, on window: NSWindow?,
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

  private static func previewText(for change: HostHookChange) -> String {
    guard change.canApply else { return change.preview.failures.joined(separator: "\n") }
    return change.preview.text.isEmpty ? nothingToChange : change.preview.text
  }
}
