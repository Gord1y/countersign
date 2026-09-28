import AppKit
import ApprovalCore

@MainActor
enum QuitPrompt {
  static let message = "Keep showing approval panels while Countersign is closed?"
  static let information =
    "Panels come from your agents' hooks, so they keep appearing after you quit."
    + " If you pause them, your agents ask in their own chat until you open Countersign again."
  static let keepShowingTitle = "Keep showing"
  static let pauseTitle = "Pause until I reopen"
  static let cancelTitle = "Cancel"
  static let dontAskAgainTitle = "Don't ask again"

  static func makeAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = information
    alert.addButton(withTitle: keepShowingTitle)
    alert.addButton(withTitle: pauseTitle)
    alert.addButton(withTitle: cancelTitle)
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = dontAskAgainTitle
    return alert
  }

  static func ask() -> QuitDecision {
    let alert = makeAlert()
    NSApplication.shared.activate()
    let response = alert.runModal()
    return QuitQuestion.decision(
      for: answer(for: response), dontAskAgain: alert.suppressionButton?.state == .on)
  }

  private static func answer(for response: NSApplication.ModalResponse) -> QuitAnswer {
    switch response {
    case .alertFirstButtonReturn: return .keepShowing
    case .alertSecondButtonReturn: return .pause
    default: return .cancel
    }
  }
}
