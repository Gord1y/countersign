import AppKit
import ApprovalCore

@MainActor
enum RestoreDefaultsPrompt {
  static let restoreTitle = "Restore Defaults"
  static let cancelTitle = "Cancel"

  static func makeAlert(pane: SettingsPane, lines: [String]) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Restore the \(pane.title) defaults?"
    alert.informativeText = lines.joined(separator: "\n")
    alert.addButton(withTitle: restoreTitle)
    alert.addButton(withTitle: cancelTitle)
    return alert
  }

  static func present(
    pane: SettingsPane, lines: [String], on window: NSWindow?, onConfirm: @escaping () -> Void
  ) {
    let alert = makeAlert(pane: pane, lines: lines)
    guard let window else {
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      onConfirm()
      return
    }
    alert.beginSheetModal(for: window) { response in
      guard response == .alertFirstButtonReturn else { return }
      onConfirm()
    }
  }
}
