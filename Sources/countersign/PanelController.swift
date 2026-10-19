import AppKit
import ApprovalCore
import SwiftUI

enum PanelKey: Sendable, Equatable {
  case digit(Int)
  case left
  case right
  case primary
  case alternate
  case secondary
  case up
  case down
}

struct PanelKeyHandler {
  let uses: (PanelKey) -> Bool
  let perform: (PanelKey) -> Void
}

enum StepAsideReason: Sendable, Equatable {
  case appSwitch(to: String?)
  case focusLost(frontmost: String?)
  case typing

  var logText: String {
    switch self {
    case .appSwitch(let bundleID):
      return bundleID.map { "app switch to \($0)" } ?? "app switch"
    case .focusLost(let bundleID):
      return bundleID.map { "focus lost, \($0) frontmost" } ?? "focus lost"
    case .typing:
      return "typing"
    }
  }
}

@MainActor
@Observable
final class PanelModel {
  let request: ApprovalRequest
  let subagentChain: [SubagentChainLink]?
  let contextGauge: ContextGauge?
  let opensContextCardOnAppear: Bool
  let chatTrackingDrift: ChatTrackingDrift?
  let fileDiffs: [FileDiff]?
  var waitingEntries: [WaitingEntry]
  var waitingCount: Int { waitingEntries.count }
  let armDuration: TimeInterval
  let snoozePresets: [TimeInterval]
  let questionNotes: Bool
  let modeAfterPlan: PlanApprovalMode
  let isTestPanel: Bool
  let sessionIdle: Bool
  let escapeKeepsWaiting: Bool
  let alwaysAllowOffer: AlwaysAllowOffer?
  let dropdown: PanelDropdownState
  let draft: PanelDraft
  private(set) var isOnScreen = false
  private(set) var hasStartedArming = false
  private(set) var isArmed = false
  private var hasFinished = false
  private var hasSnoozed = false
  var onFinish: ((ApprovalOutcome) -> Void)?
  var onSnooze: ((TimeInterval) -> Void)?
  var onCheckpointChoice: ((ContextCheckpointChoice) -> Void)?
  var onAlwaysAllow: ((AlwaysAllowOffer) -> Void)?
  var keyHandler: PanelKeyHandler?
  var onPreferredHeightChange: ((CGFloat) -> Void)?
  var onFieldFocusRestored: (() -> Void)?

  init(
    request: ApprovalRequest, waitingEntries: [WaitingEntry],
    armDuration: TimeInterval = Settings.defaultArmDelay,
    snoozePresets: [TimeInterval] = Settings.defaultSnoozePresets,
    questionNotes: Bool = Settings.defaultQuestionNotes,
    modeAfterPlan: PlanApprovalMode = Settings.defaultModeAfterPlan,
    chatTrackingDrift: ChatTrackingDrift? = nil,
    subagentChain: [SubagentChainLink]? = nil,
    contextGauge: ContextGauge? = nil,
    opensContextCardOnAppear: Bool = false,
    isTestPanel: Bool = false,
    sessionIdle: Bool = false,
    escapeKeepsWaiting: Bool = false,
    alwaysAllowOffer: AlwaysAllowOffer? = nil,
    openDropdownOnAppear: PanelDropdownID? = nil,
    draft: PanelDraft? = nil
  ) {
    self.request = request
    self.alwaysAllowOffer = alwaysAllowOffer
    self.sessionIdle = sessionIdle
    self.escapeKeepsWaiting = escapeKeepsWaiting
    self.waitingEntries = waitingEntries
    self.armDuration = armDuration
    self.snoozePresets = snoozePresets
    self.questionNotes = questionNotes
    self.modeAfterPlan = modeAfterPlan
    self.chatTrackingDrift = chatTrackingDrift
    self.isTestPanel = isTestPanel
    self.dropdown = PanelDropdownState(requestedOnAppear: openDropdownOnAppear)
    self.draft = draft ?? PanelDraft(request: request, modeAfterPlan: modeAfterPlan)
    self.fileDiffs = FileDiffBuilder.load(for: request)
    self.subagentChain = subagentChain
    self.contextGauge = contextGauge
    self.opensContextCardOnAppear = opensContextCardOnAppear
  }

  func startArming() {
    hasStartedArming = true
  }

  func markOnScreen() {
    isOnScreen = true
  }

  func markOffScreen() {
    isOnScreen = false
  }

  func noteFocus(_ field: PanelDraftField?) {
    guard isOnScreen else { return }
    draft.focusedField = field
  }

  func noteScrollOffset(_ offset: CGFloat) {
    guard isOnScreen else { return }
    draft.scrollOffset = offset
  }

  func arm() {
    isArmed = true
  }

  func finish(_ outcome: ApprovalOutcome) {
    guard isArmed, !hasFinished else { return }
    hasFinished = true
    onFinish?(outcome)
  }

  func chooseCheckpoint(_ choice: ContextCheckpointChoice, prompt: ContextCheckpointPrompt) {
    guard isArmed, !hasFinished else { return }
    onCheckpointChoice?(choice)
    finish(choice.outcome(for: prompt))
  }

  func snooze(_ seconds: TimeInterval) {
    guard isArmed, !hasFinished, !hasSnoozed else { return }
    hasSnoozed = true
    onSnooze?(seconds)
  }
}

@MainActor
final class PanelController {
  private let panel: ApprovalPanel
  private let backdrop: BackdropWindow?
  private let model: PanelModel
  private let hostingController: NSHostingController<PanelRootView>
  private var targetScreen: NSScreen?
  private var armTask: Task<Void, Never>?
  private let onStepAside: (@MainActor (StepAsideReason) -> Void)?
  private let isAfterHandoff: Bool
  private let panelSound: String
  private var keyMonitor: Any?
  private var keyWindowObserver: (any NSObjectProtocol)?
  private var workspaceObserver: (any NSObjectProtocol)?
  private var isPresented = false
  private var lastAppliedHeight: CGFloat?
  private var topEdgeY: CGFloat?
  private var showTime: Date?
  private static let settleWindow: TimeInterval = 0.2
  private static let selectionRestoreAttempts = 5
  private static let escapeKeyCode: UInt16 = 53
  private static let returnKeyCodes: Set<UInt16> = [36, 76]
  private static let deleteKeyCode: UInt16 = 51
  private static let leftArrowKeyCode: UInt16 = 123
  private static let rightArrowKeyCode: UInt16 = 124
  private static let downArrowKeyCode: UInt16 = 125
  private static let upArrowKeyCode: UInt16 = 126
  private static let defaultArmDuration: TimeInterval = Settings.defaultArmDelay
  private static let armDurationRange: ClosedRange<TimeInterval> = 0...3

  init(
    request: ApprovalRequest,
    waitingEntries: [WaitingEntry],
    armDuration: TimeInterval = PanelController.defaultArmDuration,
    snoozePresets: [TimeInterval] = Settings.defaultSnoozePresets,
    questionNotes: Bool = Settings.defaultQuestionNotes,
    modeAfterPlan: PlanApprovalMode = Settings.defaultModeAfterPlan,
    panelSound: String = Settings.defaultPanelSound,
    appearance: AppearanceChoice = Settings.defaultAppearance,
    accentColor: HexColor = Settings.defaultAccentColor,
    chatTrackingDrift: ChatTrackingDrift? = nil,
    subagentChain: [SubagentChainLink]? = nil,
    contextGauge: ContextGauge? = nil,
    isTestPanel: Bool = false,
    draft: PanelDraft? = nil,
    handoffBackdrop: BackdropWindow? = nil,
    afterHandoff: Bool = false,
    onFinish: @escaping @MainActor (ApprovalOutcome) -> Void,
    onSnooze: (@MainActor (TimeInterval) -> Void)? = nil,
    onStepAside: (@MainActor (StepAsideReason) -> Void)? = nil,
    sessionIdle: Bool = false,
    escapeKeepsWaiting: Bool = false,
    alwaysAllowOffer: AlwaysAllowOffer? = nil,
    onAlwaysAllow: ((AlwaysAllowOffer) -> Void)? = nil,
    onCheckpointChoice: ((ContextCheckpointChoice) -> Void)? = nil
  ) {
    let targetScreen = handoffBackdrop?.targetScreen ?? Self.resolveTargetScreen()
    let maxHeight = Self.maxContentHeight(screen: targetScreen)
    let panelWidth = Self.panelWidth(screen: targetScreen)
    let clampedArmDuration = min(
      max(armDuration, Self.armDurationRange.lowerBound), Self.armDurationRange.upperBound)

    let model = PanelModel(
      request: request, waitingEntries: waitingEntries, armDuration: clampedArmDuration,
      snoozePresets: snoozePresets, questionNotes: questionNotes, modeAfterPlan: modeAfterPlan,
      chatTrackingDrift: chatTrackingDrift, subagentChain: subagentChain,
      contextGauge: contextGauge, isTestPanel: isTestPanel, sessionIdle: sessionIdle,
      escapeKeepsWaiting: escapeKeepsWaiting,
      alwaysAllowOffer: alwaysAllowOffer, draft: draft)
    CountersignPalette.use(accentColor)
    let panel = ApprovalPanel()
    panel.appearance = appearance.windowAppearance
    let backdrop = handoffBackdrop ?? targetScreen.map { BackdropWindow(screen: $0) }
    let hostingController = NSHostingController(
      rootView: PanelRootView(model: model, width: panelWidth, maxHeight: maxHeight))

    self.model = model
    self.panel = panel
    self.backdrop = backdrop
    self.hostingController = hostingController
    self.targetScreen = targetScreen
    self.onStepAside = onStepAside
    self.isAfterHandoff = afterHandoff
    self.panelSound = panelSound

    panel.contentViewController = hostingController
    model.onFinish = { [weak self] outcome in
      self?.stopResponding()
      onFinish(outcome)
    }
    model.onSnooze = onSnooze
    model.onCheckpointChoice = onCheckpointChoice
    model.onAlwaysAllow = onAlwaysAllow
    panel.onEscape = { [weak model] in
      model?.finish(.noDecision)
    }
    backdrop?.onClickOutside = { [weak model] in
      guard let model else { return }
      guard !model.dropdown.isOpen else {
        model.dropdown.close()
        return
      }
      model.finish(.noDecision)
    }
    model.onPreferredHeightChange = { [weak self] height in
      self?.applyHeight(height)
    }
    model.onFieldFocusRestored = { [weak self] in
      self?.restoreFieldSelectionSoon()
    }
  }

  func layOut() {
    hostingController.view.layoutSubtreeIfNeeded()
    hostingController.view.layoutSubtreeIfNeeded()
  }

  func show() {
    showTime = Date()
    layOut()
    let fadesIn = !isAfterHandoff && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    panel.setAccessibilityTitle("Countersign approval")
    panel.alphaValue = fadesIn ? 0 : 1
    backdrop?.alphaValue = fadesIn ? 0 : 1
    backdrop?.orderFrontRegardless()
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.makeFirstResponder(nil)
    model.markOnScreen()
    isPresented = true
    installKeyMonitor()
    installStepAsideTriggers()
    announcePresentation()
    if !isAfterHandoff {
      SystemSounds.play(panelSound)
    }
    if fadesIn {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        panel.animator().alphaValue = 1
        backdrop?.animator().alphaValue = 1
      }
    }
    startArming()
  }

  var displayID: UInt32? {
    targetScreen?.displayID
  }

  var frame: NSRect {
    panel.frame
  }

  var fileDiffs: [FileDiff]? {
    model.fileDiffs
  }

  func close() {
    if isPresented {
      model.draft.fieldSelection = editableFirstResponder()?.selectedRange()
    }
    stopResponding()
    panel.orderOut(nil)
    backdrop?.orderOut(nil)
  }

  func followScreenChange() {
    guard let placed = NSScreen.placement(for: panel.frame) else { return }
    let screen = placed.screen
    let maxHeight = Self.maxContentHeight(screen: screen)
    targetScreen = screen
    hostingController.rootView = PanelRootView(
      model: model, width: Self.panelWidth(screen: screen), maxHeight: maxHeight)
    backdrop?.cover(screen)
    lastAppliedHeight = nil
    topEdgeY = nil
    applyHeight(min(panel.frame.height, maxHeight))
  }

  private func announcePresentation() {
    NSAccessibility.post(element: hostingController.view, notification: .focusedUIElementChanged)
    postAnnouncement(PanelAnnouncement.text(for: model.request))
  }

  private func postAnnouncement(_ text: String) {
    NSAccessibility.post(
      element: panel, notification: .announcementRequested,
      userInfo: [
        .announcement: text,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
  }

  private func startArming() {
    armTask?.cancel()
    let model = self.model
    model.startArming()
    guard model.armDuration > 0 else {
      model.arm()
      return
    }
    armTask = Task { [weak self] in
      let nanoseconds = UInt64(model.armDuration * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled else { return }
      model.arm()
      self?.postAnnouncement(PanelAnnouncement.ready)
    }
  }

  private func stopResponding() {
    model.markOffScreen()
    isPresented = false
    armTask?.cancel()
    removeStepAsideTriggers()
    removeKeyMonitor()
  }

  func setWaitingEntries(_ entries: [WaitingEntry]) {
    model.waitingEntries = entries
  }

  private func installKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.consumes(event) else { return event }
      return nil
    }
  }

  private func removeKeyMonitor() {
    guard let keyMonitor else { return }
    NSEvent.removeMonitor(keyMonitor)
    self.keyMonitor = nil
  }

  private func consumes(_ event: NSEvent) -> Bool {
    guard panel.isKeyWindow else { return false }
    let editor = editableFirstResponder()
    let navigationKey = Self.navigationKey(for: event)
    let isDropdownOpen = model.dropdown.isOpen
    let keyHandler = isDropdownOpen ? model.dropdown.keyHandler : model.keyHandler
    let route = KeyRouter.route(
      keyKind(for: event, navigationKey: navigationKey, keyHandler: keyHandler),
      modifiers: Self.keyModifiers(for: event.modifierFlags),
      isEditingText: editor != nil,
      hasMarkedText: editor?.hasMarkedText() == true,
      isRepeat: event.isARepeat,
      isArmed: model.isArmed,
      isDropdownOpen: isDropdownOpen)

    switch route {
    case .passThrough:
      return false
    case .swallow:
      break
    case .dismiss:
      model.finish(.noDecision)
    case .primary:
      keyHandler?.perform(.primary)
    case .alternate:
      if keyHandler?.uses(.alternate) == true {
        keyHandler?.perform(.alternate)
      }
    case .secondary:
      keyHandler?.perform(.secondary)
    case .navigate:
      if let navigationKey {
        keyHandler?.perform(navigationKey)
      }
    case .insertNewline:
      editor?.insertNewlineIgnoringFieldEditor(nil)
    case .stepAside:
      if !model.isTestPanel {
        stepAside(.typing)
      }
    case .closeDropdown:
      model.dropdown.close()
    }
    return true
  }

  private func restoreFieldSelectionSoon() {
    Task { [weak self] in
      for _ in 0..<Self.selectionRestoreAttempts {
        guard let self else { return }
        if self.restoreFieldSelection() { return }
        try? await Task.sleep(nanoseconds: 20_000_000)
      }
    }
  }

  private func restoreFieldSelection() -> Bool {
    guard let editor = editableFirstResponder() else { return false }
    let length = (editor.string as NSString).length
    let saved = model.draft.fieldSelection ?? NSRange(location: length, length: 0)
    let location = min(saved.location, length)
    editor.setSelectedRange(
      NSRange(location: location, length: min(saved.length, length - location)))
    return true
  }

  private func editableFirstResponder() -> NSTextView? {
    guard let textView = panel.firstResponder as? NSTextView, textView.isEditable else {
      return nil
    }
    return textView
  }

  private func keyKind(
    for event: NSEvent, navigationKey: PanelKey?, keyHandler: PanelKeyHandler?
  ) -> KeyKind {
    if event.keyCode == Self.escapeKeyCode {
      return .escape
    }
    if Self.returnKeyCodes.contains(event.keyCode) {
      return .returnKey
    }
    if event.keyCode == Self.deleteKeyCode {
      return .delete(usedByView: keyHandler?.uses(.secondary) == true)
    }
    if let navigationKey {
      return .navigation(usedByView: keyHandler?.uses(navigationKey) == true)
    }
    return .other
  }

  private static func keyModifiers(for flags: NSEvent.ModifierFlags) -> KeyModifiers {
    let pairs: [(NSEvent.ModifierFlags, KeyModifiers)] = [
      (.command, .command), (.control, .control), (.option, .option), (.shift, .shift),
    ]
    return pairs.reduce(into: KeyModifiers()) { modifiers, pair in
      if flags.contains(pair.0) {
        modifiers.insert(pair.1)
      }
    }
  }

  private static func navigationKey(for event: NSEvent) -> PanelKey? {
    switch event.keyCode {
    case leftArrowKeyCode:
      return .left
    case rightArrowKeyCode:
      return .right
    case upArrowKeyCode:
      return .up
    case downArrowKeyCode:
      return .down
    default:
      guard let characters = event.charactersIgnoringModifiers, characters.count == 1,
        let digit = Int(characters), (1...9).contains(digit)
      else { return nil }
      return .digit(digit)
    }
  }

  private func installStepAsideTriggers() {
    keyWindowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkFocusOnNextTurn() }
    }
    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      let activated =
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let activatedProcess = activated?.processIdentifier
      let activatedBundleID = activated?.bundleIdentifier
      MainActor.assumeIsolated {
        self?.stepAsideIfAnotherApp(activatedProcess, bundleID: activatedBundleID)
      }
    }
  }

  private func removeStepAsideTriggers() {
    if let keyWindowObserver {
      NotificationCenter.default.removeObserver(keyWindowObserver)
    }
    keyWindowObserver = nil
    if let workspaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
    }
    workspaceObserver = nil
  }

  private func stepAsideIfAnotherApp(_ activatedProcess: pid_t?, bundleID: String?) {
    guard let activatedProcess, activatedProcess != ProcessInfo.processInfo.processIdentifier
    else { return }
    stepAside(.appSwitch(to: bundleID))
  }

  private func checkFocusOnNextTurn() {
    Task { [weak self] in
      self?.stepAsideIfFocusLost()
    }
  }

  private func stepAsideIfFocusLost() {
    let ownsKeyWindow = NSApplication.shared.windows.contains { $0.isKeyWindow }
    guard !ownsKeyWindow else { return }
    stepAside(.focusLost(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier))
  }

  private func stepAside(_ reason: StepAsideReason) {
    guard isPresented else { return }
    onStepAside?(reason)
  }

  static func resolveTargetScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
      return screen
    }
    return NSScreen.main ?? NSScreen.screens.first
  }

  static func maxContentHeight(screen: NSScreen?) -> CGFloat {
    guard let screen else { return 600 }
    return screen.visibleFrame.height * 0.8
  }

  static func panelWidth(screen: NSScreen?) -> CGFloat {
    guard let screen else { return PanelMetrics.width }
    return min(PanelMetrics.width, screen.visibleFrame.width * 0.9)
  }

  private func applyHeight(_ desiredHeight: CGFloat) {
    guard let screen = targetScreen else { return }
    let visibleFrame = screen.visibleFrame
    let width = Self.panelWidth(screen: screen)
    let maxHeight = Self.maxContentHeight(screen: screen)
    let clampedDesired = min(max(desiredHeight, 1), maxHeight)

    let hasSettled = showTime.map { Date().timeIntervalSince($0) >= Self.settleWindow } ?? false

    let height: CGFloat
    let y: CGFloat
    if hasSettled {
      height = max(clampedDesired, lastAppliedHeight ?? clampedDesired)
      let top = topEdgeY ?? (visibleFrame.midY + height / 2)
      var candidateY = top - height
      if candidateY < visibleFrame.minY {
        candidateY = visibleFrame.minY
      }
      topEdgeY = candidateY + height
      y = candidateY
    } else {
      height = clampedDesired
      y = visibleFrame.midY - height / 2
      topEdgeY = nil
    }
    lastAppliedHeight = height

    let x = visibleFrame.midX - width / 2
    panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
  }
}
