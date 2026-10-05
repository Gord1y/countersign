import AppKit
import ApprovalCore

@MainActor
enum SameDelaysPrompt {
  static let confirmTitle = "Use Same Delays"
  static let cancelTitle = "Cancel"

  static func makeAlert(agents: [ApprovalCore.Host]) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "Use the same delays for every agent?"
    alert.informativeText = PreferenceOverrides.sameDelaysPromptText(agents: agents)
    alert.addButton(withTitle: confirmTitle)
    alert.addButton(withTitle: cancelTitle)
    return alert
  }

  static func present(
    agents: [ApprovalCore.Host], on window: NSWindow?, onConfirm: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    let alert = makeAlert(agents: agents)
    guard let window else {
      if alert.runModal() == .alertFirstButtonReturn {
        onConfirm()
      } else {
        onCancel()
      }
      return
    }
    alert.beginSheetModal(for: window) { response in
      if response == .alertFirstButtonReturn {
        onConfirm()
      } else {
        onCancel()
      }
    }
  }
}
