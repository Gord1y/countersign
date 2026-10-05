import AppKit

final class SettingsSheetWindow: NSWindow {
  override var canBecomeKey: Bool { true }

  convenience init() {
    self.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    isReleasedWhenClosed = false
  }
}
