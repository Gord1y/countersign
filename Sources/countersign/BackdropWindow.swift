import AppKit
import ApprovalCore

private final class BackdropContentView: NSView {
  var onClick: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true

    let effectView = NSVisualEffectView(frame: bounds)
    effectView.autoresizingMask = [.width, .height]
    effectView.material = .fullScreenUI
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.alphaValue = 0.85
    addSubview(effectView)

    let overlay = NSView(frame: bounds)
    overlay.autoresizingMask = [.width, .height]
    overlay.wantsLayer = true
    overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    addSubview(overlay)
  }

  required init?(coder: NSCoder) {
    fatalError("BackdropContentView does not support NSCoding")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    onClick?()
  }
}

final class BackdropWindow: NSPanel {
  var onClickOutside: (() -> Void)? {
    didSet { backdropContentView.onClick = onClickOutside }
  }

  private(set) var targetScreen: NSScreen
  private let backdropContentView: BackdropContentView

  init(screen: NSScreen) {
    let contentView = BackdropContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
    self.backdropContentView = contentView
    self.targetScreen = screen
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    self.contentView = contentView
    configure(screen: screen)
  }

  required init?(coder: NSCoder) {
    fatalError("BackdropWindow does not support NSCoding")
  }

  private func configure(screen: NSScreen) {
    setFrame(screen.frame, display: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isFloatingPanel = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    hidesOnDeactivate = false
    isMovable = false
    animationBehavior = .none
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func showAtFullOpacity() {
    alphaValue = 1
    orderFrontRegardless()
    display()
    CATransaction.flush()
  }

  func cover(_ screen: NSScreen) {
    targetScreen = screen
    setFrame(screen.frame, display: true)
  }
}

extension NSScreen {
  var displayID: UInt32? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  static func screen(displayID: UInt32) -> NSScreen? {
    screens.first { $0.displayID == displayID }
  }

  static func placement(for window: NSRect) -> (screen: NSScreen, frame: NSRect)? {
    let screens = screens
    let areas = screens.map {
      ScreenPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
    }
    guard let placement = ScreenPlacement.place(window, on: areas),
      screens.indices.contains(placement.screenIndex)
    else { return nil }
    return (screens[placement.screenIndex], placement.frame)
  }
}
