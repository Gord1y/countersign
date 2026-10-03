import AppKit

@MainActor
enum RemoveRulePrompt {
  static let title = "Remove this rule?"
  static let removeTitle = "Remove"
  static let cancelTitle = "Cancel"

  static func makeAlert(lines: [String]) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = lines.joined(separator: "\n")
    alert.addButton(withTitle: removeTitle)
    alert.addButton(withTitle: cancelTitle)
    return alert
  }

  static func present(lines: [String], on window: NSWindow?, onConfirm: @escaping () -> Void) {
    let alert = makeAlert(lines: lines)
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
