import AppKit

@MainActor
enum TestPanelRefusalAlert {
  static let message = "The test panel didn't show"
  static let okTitle = "OK"

  static func makeAlert(refusal: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = sentence(refusal)
    alert.addButton(withTitle: okTitle)
    return alert
  }

  static func show(refusal: String) {
    let alert = makeAlert(refusal: refusal)
    NSApplication.shared.activate()
    alert.runModal()
  }

  private static func sentence(_ refusal: String) -> String {
    refusal.prefix(1).uppercased() + refusal.dropFirst() + "."
  }
}
