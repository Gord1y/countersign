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

enum StepAsideReason: String {
  case appSwitch = "app switch"
  case focusLost = "focus lost"
  case typing
}

@MainActor
@Observable
final class PanelModel {
  let request: ApprovalRequest
  let subagentChain: [SubagentChainLink]?
  let chatTrackingDrift: ChatTrackingDrift?
  let fileDiffs: [FileDiff]?
  var waitingEntries: [WaitingEntry]
  var waitingCount: Int { waitingEntries.count }
  let armDuration: TimeInterval
  let snoozeMinutes: [Int]
  let questionNotes: Bool
  let modeAfterPlan: PlanApprovalMode
  let isTestPanel: Bool
  let dropdown: PanelDropdownState
  private(set) var hasStartedArming = false
  private(set) var isArmed = false
  private var hasFinished = false
  private var hasSnoozed = false
  var onFinish: ((ApprovalOutcome) -> Void)?
  var onSnooze: ((TimeInterval) -> Void)?
  var keyHandler: PanelKeyHandler?
  var onPreferredHeightChange: ((CGFloat) -> Void)?

  init(
    request: ApprovalRequest, waitingEntries: [WaitingEntry], armDuration: TimeInterval = 0.8,
    snoozeMinutes: [Int] = Settings.defaultSnoozeMinutes,
    questionNotes: Bool = Settings.defaultQuestionNotes,
    modeAfterPlan: PlanApprovalMode = Settings.defaultModeAfterPlan,
    chatTrackingDrift: ChatTrackingDrift? = nil,
    isTestPanel: Bool = false,
    openDropdownOnAppear: PanelDropdownID? = nil
  ) {
    self.request = request
    self.waitingEntries = waitingEntries
    self.armDuration = armDuration
    self.snoozeMinutes = snoozeMinutes
    self.questionNotes = questionNotes
    self.modeAfterPlan = modeAfterPlan
    self.chatTrackingDrift = chatTrackingDrift
    self.isTestPanel = isTestPanel
    self.dropdown = PanelDropdownState(requestedOnAppear: openDropdownOnAppear)
    self.fileDiffs = FileDiffBuilder.load(for: request)
    if let transcriptPath = request.transcriptPath, let agentID = request.agentID {
      self.subagentChain = SubagentChainReader.chain(
        transcriptPath: transcriptPath, agentID: agentID)
    } else {
      self.subagentChain = nil
    }
  }

  func startArming() {
    hasStartedArming = true
  }

  func arm() {
    isArmed = true
  }

  func finish(_ outcome: ApprovalOutcome) {
    guard isArmed, !hasFinished else { return }
    hasFinished = true
    onFinish?(outcome)
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
  private let targetScreen: NSScreen?
  private var armTask: Task<Void, Never>?
  private let onStepAside: (@MainActor (StepAsideReason) -> Void)?
  private let isAfterHandoff: Bool
  private var keyMonitor: Any?
  private var keyWindowObserver: (any NSObjectProtocol)?
  private var workspaceObserver: (any NSObjectProtocol)?
  private var isPresented = false
  private var lastAppliedHeight: CGFloat?
  private var topEdgeY: CGFloat?
  private var showTime: Date?
  private static let settleWindow: TimeInterval = 0.2
  private static let escapeKeyCode: UInt16 = 53
  private static let returnKeyCodes: Set<UInt16> = [36, 76]
  private static let deleteKeyCode: UInt16 = 51
  private static let leftArrowKeyCode: UInt16 = 123
  private static let rightArrowKeyCode: UInt16 = 124
  private static let downArrowKeyCode: UInt16 = 125
  private static let upArrowKeyCode: UInt16 = 126
  private static let defaultArmDuration: TimeInterval = 0.8
  private static let armDurationRange: ClosedRange<TimeInterval> = 0...3

  init(
    request: ApprovalRequest,
    waitingEntries: [WaitingEntry],
    armDuration: TimeInterval = PanelController.defaultArmDuration,
    snoozeMinutes: [Int] = Settings.defaultSnoozeMinutes,
    questionNotes: Bool = Settings.defaultQuestionNotes,
    modeAfterPlan: PlanApprovalMode = Settings.defaultModeAfterPlan,
    appearance: AppearanceChoice = Settings.defaultAppearance,
    accentColor: HexColor = Settings.defaultAccentColor,
    chatTrackingDrift: ChatTrackingDrift? = nil,
    isTestPanel: Bool = false,
    handoffBackdrop: BackdropWindow? = nil,
    afterHandoff: Bool = false,
    onFinish: @escaping @MainActor (ApprovalOutcome) -> Void,
    onSnooze: (@MainActor (TimeInterval) -> Void)? = nil,
    onStepAside: (@MainActor (StepAsideReason) -> Void)? = nil
  ) {
    let targetScreen = handoffBackdrop?.targetScreen ?? Self.resolveTargetScreen()
    let maxHeight = Self.maxContentHeight(screen: targetScreen)
    let panelWidth = Self.panelWidth(screen: targetScreen)
    let clampedArmDuration = min(
      max(armDuration, Self.armDurationRange.lowerBound), Self.armDurationRange.upperBound)

    let model = PanelModel(
      request: request, waitingEntries: waitingEntries, armDuration: clampedArmDuration,
      snoozeMinutes: snoozeMinutes, questionNotes: questionNotes, modeAfterPlan: modeAfterPlan,
      chatTrackingDrift: chatTrackingDrift, isTestPanel: isTestPanel)
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

    panel.contentViewController = hostingController
    model.onFinish = { [weak self] outcome in
      self?.stopResponding()
      onFinish(outcome)
    }
    model.onSnooze = onSnooze
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
  }

  func layOut() {
    hostingController.view.layoutSubtreeIfNeeded()
    hostingController.view.layoutSubtreeIfNeeded()
  }

  func show() {
    showTime = Date()
    layOut()
    let fadesIn = !isAfterHandoff
    panel.alphaValue = fadesIn ? 0 : 1
    backdrop?.alphaValue = fadesIn ? 0 : 1
    backdrop?.orderFrontRegardless()
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.makeFirstResponder(nil)
    isPresented = true
    installKeyMonitor()
    installStepAsideTriggers()
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

  var fileDiffs: [FileDiff]? {
    model.fileDiffs
  }

  func close() {
    stopResponding()
    panel.orderOut(nil)
    backdrop?.orderOut(nil)
  }

  private func startArming() {
    armTask?.cancel()
    let model = self.model
    model.startArming()
    guard model.armDuration > 0 else {
      model.arm()
      return
    }
    armTask = Task {
      let nanoseconds = UInt64(model.armDuration * 1_000_000_000)
      try? await Task.sleep(nanoseconds: nanoseconds)
      guard !Task.isCancelled else { return }
      model.arm()
    }
  }

  private func stopResponding() {
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
      } else {
        keyHandler?.perform(.primary)
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
      stepAside(.typing)
    case .closeDropdown:
      model.dropdown.close()
    }
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
      MainActor.assumeIsolated { self?.stepAsideIfAnotherApp(activatedProcess) }
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

  private func stepAsideIfAnotherApp(_ activatedProcess: pid_t?) {
    guard let activatedProcess, activatedProcess != ProcessInfo.processInfo.processIdentifier
    else { return }
    stepAside(.appSwitch)
  }

  private func checkFocusOnNextTurn() {
    Task { [weak self] in
      self?.stepAsideIfFocusLost()
    }
  }

  private func stepAsideIfFocusLost() {
    let ownsKeyWindow = NSApplication.shared.windows.contains { $0.isKeyWindow }
    guard !ownsKeyWindow else { return }
    stepAside(.focusLost)
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
