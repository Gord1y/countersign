import AppKit
import ApprovalCore
import SwiftUI

@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
  static let title = "Set Up Countersign"

  let model: SetupModel
  private let onOpenSettings: @MainActor () -> Void
  private let onClose: @MainActor () -> Void
  private var isFinished = false

  init(
    model: SetupModel, onOpenSettings: @escaping @MainActor () -> Void,
    onClose: @escaping @MainActor () -> Void
  ) {
    self.model = model
    self.onOpenSettings = onOpenSettings
    self.onClose = onClose
    let hostingController = NSHostingController(rootView: SetupView(model: model))
    hostingController.sizingOptions = [.preferredContentSize]
    let window = NSWindow(contentViewController: hostingController)
    window.styleMask = [.titled, .closable]
    window.title = Self.title
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.fullScreenNone]
    super.init(window: window)
    window.delegate = self
    model.requestDone = { [weak self] in self?.window?.performClose(nil) }
    model.requestOpenSettings = { [weak self] in self?.openSettings() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  func show() {
    writeShownMarker()
    model.settings.refreshFromDisk()
    NSApplication.shared.setActivationPolicy(.regular)
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    window?.orderFrontRegardless()
    NSApplication.shared.activate()
  }

  func windowWillClose(_ notification: Notification) {
    finish(then: onClose)
  }

  private func openSettings() {
    finish(then: onOpenSettings)
    window?.close()
  }

  private func finish(then action: @MainActor () -> Void) {
    guard !isFinished else { return }
    isFinished = true
    action()
  }

  private func writeShownMarker() {
    let file = model.settings.environment.paths.setupShownFile
    try? FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data().write(to: file)
  }
}

@MainActor
enum SetupWindowCommand {
  static func openWindow() -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = SetupApplicationDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) {
      application.run()
    }
    exit(0)
  }
}

@MainActor
private final class SetupApplicationDelegate: NSObject, NSApplicationDelegate {
  private var setupController: SetupWindowController?
  private var settingsController: SettingsWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    SettingsMenu.install()
    let environment = SettingsEnvironment.current()
    let controller = SetupWindowController(
      model: SetupModel(settings: SettingsModel(environment: environment)),
      onOpenSettings: { [weak self] in self?.openSettings() }, onClose: { exit(0) })
    setupController = controller
    controller.show()
  }

  private func openSettings() {
    let controller = SettingsWindowController(
      model: SettingsModel(environment: .current()), onClose: { exit(0) })
    settingsController = controller
    controller.show()
  }

  func applicationWillTerminate(_ notification: Notification) {
    settingsController?.model.commitEditing()
  }
}
