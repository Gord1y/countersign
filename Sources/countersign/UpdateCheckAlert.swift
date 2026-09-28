import AppKit
import ApprovalCore

@MainActor
enum UpdateCheckAlert {
  static func makeAlert(for answer: UpdateCheckAnswer) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = answer.title
    alert.informativeText = answer.message
    for button in answer.buttons {
      alert.addButton(withTitle: button.title)
    }
    return alert
  }

  static func ask(for answer: UpdateCheckAnswer) -> UpdateCheckAnswerButton? {
    let alert = makeAlert(for: answer)
    NSApplication.shared.activate()
    let response = alert.runModal()
    let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    guard answer.buttons.indices.contains(index) else { return nil }
    return answer.buttons[index]
  }
}
