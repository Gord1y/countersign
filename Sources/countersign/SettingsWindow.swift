import AppKit
import ApprovalCore
import SwiftUI

@MainActor
enum SettingsCommand {
  static let usage = "usage: countersign settings"

  static func run(_ arguments: [String]) {
    guard arguments.isEmpty else {
      CommandLineOutput.fail(usage)
    }
    openWindow()
  }

  static func openWindow() -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = SettingsApplicationDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) {
      application.run()
    }
    exit(0)
  }
}

@MainActor
private final class SettingsApplicationDelegate: NSObject, NSApplicationDelegate {
  private var controller: SettingsWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    SettingsMenu.install()
    let controller = SettingsWindowController(
      model: SettingsModel(environment: .current()), onClose: { exit(0) })
    self.controller = controller
    controller.show()
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller?.model.commitEditing()
  }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  static let title = "Countersign"
  static let frameAutosaveName = "Countersign Settings"
  static let statusRefreshInterval: TimeInterval = 2

  let model: SettingsModel
  private let window: NSWindow
  private let onClose: @MainActor () -> Void
  private var statusTimer: Timer?
  private var screenObserver: (any NSObjectProtocol)?
  private var tourWindow: NSWindow?
  private var tourHostingController: NSHostingController<FirstRunTourView>?

  init(model: SettingsModel, onClose: @escaping @MainActor () -> Void) {
    self.model = model
    self.onClose = onClose
    window = NSWindow(
      contentRect: NSRect(origin: .zero, size: SettingsWindowPlacement.defaultContentSize),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    super.init()
    window.title = Self.title
    window.isReleasedWhenClosed = false
    window.contentMinSize = SettingsWindowPlacement.minimumContentSize
    window.collectionBehavior = [.fullScreenNone]
    let hostingView = NSHostingView(rootView: SettingsRootView(model: model))
    hostingView.sizingOptions = []
    window.contentView = hostingView
    window.delegate = self
    placeWindow()
    model.requestClose = { [weak self] in self?.window.performClose(nil) }
    model.requestTour = { [weak self] in self?.presentTourIfNeeded(force: true) }
    window.appearance = model.appearance.windowAppearance
    model.applyAppearance = { [weak self] appearance in
      guard let window = self?.window,
        window.appearance?.name != appearance.windowAppearance?.name
      else { return }
      window.appearance = appearance.windowAppearance
    }
    let timer = Timer(
      timeInterval: Self.statusRefreshInterval, target: self,
      selector: #selector(statusTimerFired), userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)
    statusTimer = timer
  }

  @objc private func statusTimerFired() {
    model.refreshStatus()
  }

  func show(forceTour: Bool = false) {
    model.beginVisit()
    NSApplication.shared.setActivationPolicy(.regular)
    keepOnUsableScreen()
    observeScreenChanges()
    Self.configurePlaceholderIconIfNeeded(
      scale: (window.screen ?? NSScreen.main)?.backingScaleFactor ?? 2)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    NSApplication.shared.activate()
    presentTourIfNeeded(force: forceTour)
  }

  private func presentTourIfNeeded(force: Bool) {
    guard tourWindow == nil else { return }
    let tourShownFile = model.environment.paths.tourShownFile
    guard force || !FileManager.default.fileExists(atPath: tourShownFile.path) else { return }
    presentTour(step: .wireAgents)
  }

  private func presentTour(step: FirstRunTourStep) {
    let hostingController = NSHostingController(rootView: tourView(for: step))
    let sheetWindow = SettingsSheetWindow()
    sheetWindow.contentViewController = hostingController
    tourWindow = sheetWindow
    tourHostingController = hostingController
    window.beginSheet(sheetWindow)
  }

  private func tourView(for step: FirstRunTourStep) -> FirstRunTourView {
    FirstRunTourView(
      step: step,
      onSkip: { [weak self] in self?.finishTour() },
      onBack: { [weak self] in self?.moveTour(from: step, forward: false) },
      onNext: { [weak self] in self?.moveTour(from: step, forward: true) })
  }

  private func moveTour(from step: FirstRunTourStep, forward: Bool) {
    let nextRawValue = step.rawValue + (forward ? 1 : -1)
    guard let nextStep = FirstRunTourStep(rawValue: nextRawValue) else {
      finishTour()
      return
    }
    tourHostingController?.rootView = tourView(for: nextStep)
  }

  private func finishTour() {
    markTourShown()
    guard let tourWindow else { return }
    window.endSheet(tourWindow)
    self.tourWindow = nil
    tourHostingController = nil
  }

  private func markTourShown() {
    let tourShownFile = model.environment.paths.tourShownFile
    try? FileManager.default.createDirectory(
      at: tourShownFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: tourShownFile.path, contents: nil)
  }

  func windowDidBecomeKey(_ notification: Notification) {
    model.refreshFromDisk()
  }

  func windowWillClose(_ notification: Notification) {
    if let tourWindow {
      window.endSheet(tourWindow)
      self.tourWindow = nil
      tourHostingController = nil
    }
    model.commitEditing()
    model.closeTestCards()
    statusTimer?.invalidate()
    statusTimer = nil
    if let screenObserver {
      NotificationCenter.default.removeObserver(screenObserver)
    }
    screenObserver = nil
    NSApplication.shared.setActivationPolicy(.accessory)
    onClose()
  }

  private static var didConfigurePlaceholderIcon = false

  private func observeScreenChanges() {
    guard screenObserver == nil else { return }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.keepOnUsableScreen() }
    }
  }

  private func keepOnUsableScreen() {
    guard let placed = NSScreen.placement(for: window.frame), placed.frame != window.frame
    else { return }
    window.setFrame(placed.frame, display: true)
  }

  private static func configurePlaceholderIconIfNeeded(scale: CGFloat) {
    guard !didConfigurePlaceholderIcon else { return }
    didConfigurePlaceholderIcon = true
    guard Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil else { return }
    let renderer = ImageRenderer(content: CountersignMark().frame(width: 256, height: 256))
    renderer.scale = scale
    guard let image = renderer.nsImage else { return }
    NSApplication.shared.applicationIconImage = image
  }

  private func placeWindow() {
    let restored = window.setFrameUsingName(Self.frameAutosaveName)
    let usable = SettingsWindowPlacement.isUsable(
      frame: window.frame, contentSize: window.contentRect(forFrameRect: window.frame).size,
      visibleFrames: NSScreen.screens.map(\.visibleFrame))
    if !restored || !usable {
      NSWindow.removeFrame(usingName: Self.frameAutosaveName)
      let available = (window.screen ?? NSScreen.main).map {
        window.contentRect(forFrameRect: $0.visibleFrame).size
      }
      window.setContentSize(
        SettingsWindowPlacement.defaultContentSize(
          fitting: available ?? SettingsWindowPlacement.defaultContentSize))
      window.center()
    }
    window.setFrameAutosaveName(Self.frameAutosaveName)
  }
}

@MainActor
enum SettingsMenu {
  static func install() {
    guard NSApplication.shared.mainMenu == nil else { return }
    let main = NSMenu()

    let windowMenu = NSMenu(title: SettingsWindowController.title)
    windowMenu.addItem(
      withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let windowItem = NSMenuItem()
    windowItem.submenu = windowMenu
    main.addItem(windowItem)

    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let editItem = NSMenuItem()
    editItem.submenu = editMenu
    main.addItem(editItem)

    NSApplication.shared.mainMenu = main
  }
}
