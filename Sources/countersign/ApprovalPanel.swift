import AppKit

final class ApprovalPanel: NSPanel {
  static let floatingLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)

  var onEscape: (() -> Void)?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: 400),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    configure()
  }

  required init?(coder: NSCoder) {
    fatalError("ApprovalPanel does not support NSCoding")
  }

  private func configure() {
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isFloatingPanel = true
    level = Self.floatingLevel
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    hidesOnDeactivate = false
    isMovable = false
    becomesKeyOnlyIfNeeded = false
    animationBehavior = .none
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }
}
