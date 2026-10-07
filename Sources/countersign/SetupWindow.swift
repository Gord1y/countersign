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
    sizeWindowToContent()
    window?.center()
    window?.makeKeyAndOrderFront(nil)
    window?.orderFrontRegardless()
    NSApplication.shared.activate()
  }

  func windowWillClose(_ notification: Notification) {
    finish(then: onClose)
  }

  private func sizeWindowToContent() {
    guard let contentView = window?.contentView else { return }
    contentView.layoutSubtreeIfNeeded()
    contentView.layoutSubtreeIfNeeded()
    window?.setContentSize(contentView.fittingSize)
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
  private var isSwitchingToSetup = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    SettingsMenu.install()
    openSetup()
  }

  private func openSetup() {
    isSwitchingToSetup = true
    settingsController?.model.requestClose?()
    isSwitchingToSetup = false
    settingsController = nil
    let controller = SetupWindowController(
      model: SetupModel(settings: SettingsModel(environment: .current())),
      onOpenSettings: { [weak self] in self?.openSettings() }, onClose: { exit(0) })
    setupController = controller
    controller.show()
  }

  private func openSettings() {
    let controller = SettingsWindowController(
      model: SettingsModel(environment: .current()),
      onClose: { [weak self] in
        guard self?.isSwitchingToSetup != true else { return }
        exit(0)
      })
    controller.model.requestSetup = { [weak self] in self?.openSetup() }
    settingsController = controller
    controller.show()
  }

  func applicationWillTerminate(_ notification: Notification) {
    settingsController?.model.commitEditing()
  }
}
