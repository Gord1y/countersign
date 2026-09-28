import AppKit

@MainActor
final class PanelApplication: NSObject, NSApplicationDelegate {
  private let application: NSApplication
  private let log: (String) -> Void
  private var returnTarget: NSRunningApplication?
  private var controller: PanelController?
  private var hasFinishedLaunching = false
  private var hasClickedIntoPanel = false
  private var launchActions: [@MainActor () -> Void] = []

  init(log: @escaping (String) -> Void) {
    returnTarget = NSWorkspace.shared.frontmostApplication
    application = NSApplication.shared
    self.log = log
    super.init()
    application.setActivationPolicy(.accessory)
    application.delegate = self
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(otherApplicationActivated(_:)),
      name: NSWorkspace.didActivateApplicationNotification, object: nil)
    _ = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      if event.window is ApprovalPanel {
        self?.hasClickedIntoPanel = true
      }
      return event
    }
  }

  func show(_ controller: PanelController) {
    hasClickedIntoPanel = false
    self.controller = controller
    if hasFinishedLaunching {
      controller.show()
    }
  }

  func afterLaunch(_ action: @escaping @MainActor () -> Void) {
    if hasFinishedLaunching {
      action()
    } else {
      launchActions.append(action)
    }
  }

  func run() {
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    hasFinishedLaunching = true
    let actions = launchActions
    launchActions = []
    for action in actions {
      action()
    }
    controller?.show()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    guard !hasClickedIntoPanel else { return }
    guard let target = returnTarget, target != NSRunningApplication.current else {
      log("activation guard fired, deactivating")
      application.deactivate()
      return
    }
    log("activation guard fired, returning to \(target.localizedName ?? "-")")
    application.yieldActivation(to: target)
    if !target.activate(from: NSRunningApplication.current, options: []) {
      application.deactivate()
    }
  }

  @objc private func otherApplicationActivated(_ notification: Notification) {
    guard
      let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        as? NSRunningApplication,
      activated != NSRunningApplication.current
    else { return }
    returnTarget = activated
  }
}
