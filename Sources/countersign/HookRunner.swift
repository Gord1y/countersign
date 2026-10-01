import AppKit
import ApprovalCore
import Foundation

@MainActor
enum HookRunner {
  static func run(_ arguments: [String]) -> Never {
    let startedAt = ContinuousClock.now
    signal(SIGPIPE, SIG_IGN)
    let paths = AppPaths.standard
    let log = EventLog(file: paths.logFile)
    log.rotateIfNeeded()
    log.redirectStandardError()

    guard let options = HookOptions.parse(arguments) else {
      log.write("bad arguments")
      exit(0)
    }

    let (configFile, configLogLines) = ConfigFileLoader.load(
      paths: paths, soundNames: SystemSounds.installedNames)
    for line in configLogLines {
      log.write("config: \(line)")
    }
    let settings = Settings.resolve(file: configFile, host: options.host)

    let input = FileHandle.standardInput.readDataToEndOfFile()

    if options.event == .waiting {
      WaitingRecorder.recordTurnEnded(
        input: input, host: options.host, settings: settings, paths: paths, log: log)
    }

    WaitingRecorder.clearRecord(input: input, host: options.host, paths: paths, log: log)

    if PauseSwitch(file: paths.pauseFile).isPaused {
      log.write("paused")
      exit(0)
    }

    if options.host == .claude, ClaudeAdapter.eventName(of: input) == ContextHookSetup.eventName {
      ContextCheckpointRunner.run(
        input: input, settings: settings, paths: paths, log: log, startedAt: startedAt)
    }

    let request: ApprovalRequest
    do {
      request = try options.host.parse(input)
    } catch {
      log.write("unparseable input: \(describe(error))")
      exit(0)
    }
    log.write(
      "start host=\(options.host.rawValue) tool=\(request.toolName) "
        + "project=\(request.projectName) agent=\(request.agentType ?? "-")")

    if request.runsInSandbox {
      log.write("skipped: sandboxed command")
      exit(0)
    }

    if !request.isAskedAbout {
      log.write("skipped: \(request.toolName) not asked about")
      exit(0)
    }

    let hostApp = HostApp.resolve()
    if let hostApp {
      log.write("host app: \(hostApp.localizedName) (\(hostApp.bundleIdentifier))")
    } else {
      log.write("host app: unknown")
    }

    if options.host == .claude {
      let registryEntry = SessionRegistry.findEntry(
        sessionID: request.sessionID, in: paths.claudeSessionsDirectory)
      if case .skip(let kind) = HeadlessSessionGate.decide(
        registryEntry: registryEntry, includeHeadlessSessions: settings.includeHeadlessSessions)
      {
        log.write("skipped: non-interactive session (kind=\(kind))")
        exit(0)
      }
    }

    showPanel(
      for: request, mode: .hook, settings: settings, paths: paths, log: log, startedAt: startedAt,
      hostApp: hostApp)
  }

  static func showPanel(
    for request: ApprovalRequest, mode: PanelRunMode, settings: Settings, paths: AppPaths,
    log: EventLog, startedAt: ContinuousClock.Instant, hostApp: HostApp?,
    checkpoint: ContextCheckpointSession? = nil
  ) -> Never {
    let clock = ContinuousClock()
    let host = request.host
    let waitingHandBack = WaitingHandBack(
      request: request, mode: mode, settings: settings, hostApp: hostApp, paths: paths, log: log)
    let watcher =
      mode.followsChat
      ? ResolutionWatcher(request: request, sessionsDirectory: paths.claudeSessionsDirectory)
      : nil
    let pauseSwitch = PauseSwitch(file: paths.pauseFile)
    let quietState = QuietState(
      paths: paths, schedule: QuietSchedule(windows: settings.quietHours))
    func isPaused() -> Bool {
      mode.honorsPause && pauseSwitch.isPaused
    }
    func abandonReason() -> String? {
      if let reason = watcher?.poll() {
        return reason.rawValue
      }
      if let reason = checkpoint?.abandonReason() {
        return reason
      }
      if isPaused() {
        return "paused"
      }
      return nil
    }
    func handBackIsDue() -> Bool {
      mode.handsBackBeforeTimeout
        && TimeoutHandBack.isDue(host: host, elapsed: clock.now - startedAt)
    }

    let graceSeconds = mode.honorsGracePeriod ? settings.graceSeconds : 0
    let graceDeadline = clock.now.advanced(by: .milliseconds(Int(graceSeconds * 1000)))
    while true {
      if let reason = abandonReason() {
        log.write("resolved during grace: \(reason)")
        exit(0)
      }
      if handBackIsDue() {
        handBack(host: host, log: log, waiting: waitingHandBack)
      }
      guard clock.now < graceDeadline else { break }
      Thread.sleep(forTimeInterval: 0.25)
    }

    let queue = TicketQueue(directory: paths.queueDirectory, lockFile: paths.displayLockFile)
    if mode.waitsForApprovalsFirst {
      waitUntilNoApprovalIsQueued(queue: queue, log: log, abandonReason: abandonReason)
    }
    let subagentChain = SubagentDescription.chain(for: request)
    var ticket: Ticket
    do {
      ticket = try queue.enqueue(
        TicketSummary(
          request: request, agentDescription: SubagentDescription.resolve(from: subagentChain),
          isTestPanel: mode.isTest)
      )
    } catch {
      log.write("failed to enqueue: \(error)")
      exit(0)
    }
    queue.removeOnTermination(ticket)

    var menuOutcome: ApprovalOutcome?
    var showsWithoutIdle = false
    func shouldStopWaiting() -> Bool {
      if abandonReason() != nil || handBackIsDue() {
        return true
      }
      guard let answer = queue.takeMenuAnswer(for: ticket) else { return false }
      switch receiveMenuAnswer(answer, ticket: ticket, queue: queue, log: log) {
      case .finish(let outcome):
        menuOutcome = outcome
        return true
      case .moved(let moved):
        ticket = moved.ticket
        showsWithoutIdle = moved.place == .front
        return false
      case .ignored:
        return false
      }
    }
    let turn =
      mode.waitsItsTurn
      ? queue.waitForTurn(ticket, pollInterval: 0.25, shouldAbandon: shouldStopWaiting)
      : TestPanelCommand.takeDisplay(queue: queue, ticket: ticket, log: log)
    let lease: DisplayLease?
    switch turn {
    case .display(let acquired):
      lease = acquired
    case .nextInLine:
      lease = nil
    case .abandoned:
      if let menuOutcome {
        writeReply(menuOutcome, host: host)
        log.write("outcome: \(describe(menuOutcome))")
        recordDecision(
          request: request,
          answer: DecisionAnswer.answer(
            for: menuOutcome, checkpointChoice: nil, isCheckpoint: false),
          history: DecisionHistory(paths: paths), log: log)
        queue.remove(ticket)
        if menuOutcome == .noDecision {
          waitingHandBack.record()
        }
        exit(0)
      }
      let reason = abandonReason()
      queue.remove(ticket)
      if reason == nil, handBackIsDue() {
        handBack(host: host, log: log, waiting: waitingHandBack)
      }
      log.write("resolved while queued: \(reason ?? "unknown")")
      if !mode.isTest, let reason, reason != "paused" {
        recordDecision(
          request: request, answer: .resolvedElsewhere,
          history: DecisionHistory(paths: paths), log: log)
      }
      exit(0)
    }

    let app = PanelApplication(log: { log.write($0) })

    let initialWaitingEntries = queue.waitingEntries(excluding: ticket)
    let activityGate = ActivityGate(idleSeconds: settings.idleSeconds)
    let displayWatch = DisplayWatch(
      app: app, request: request, mode: mode, queue: queue, ticket: ticket, lease: lease,
      log: log, activityGate: activityGate, quietState: quietState, settings: settings,
      subagentChain: subagentChain, waitingEntries: initialWaitingEntries,
      sessionsDirectory: paths.claudeSessionsDirectory, history: DecisionHistory(paths: paths),
      hostApp: hostApp, checkpoint: checkpoint, showsWithoutIdle: showsWithoutIdle,
      waitingHandBack: waitingHandBack,
      cardSlots: WaitingStore(directory: paths.waitingDirectory),
      abandonReason: abandonReason, handBackIsDue: handBackIsDue, isPaused: isPaused)
    let timer = Timer(
      timeInterval: 0.25, target: displayWatch, selector: #selector(DisplayWatch.tick),
      userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)

    app.run()
    exit(0)
  }

  private static func waitUntilNoApprovalIsQueued(
    queue: TicketQueue, log: EventLog, abandonReason: () -> String?
  ) {
    var hasLoggedWait = false
    while queue.approvalCount(excluding: nil) > 0 {
      if !hasLoggedWait {
        hasLoggedWait = true
        log.write("waiting for approvals")
      }
      if let reason = abandonReason() {
        log.write("resolved while waiting for approvals: \(reason)")
        exit(0)
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
  }

  enum MenuAnswerEffect {
    case finish(ApprovalOutcome)
    case moved(ShowNowResult)
    case ignored
  }

  static func receiveMenuAnswer(
    _ answer: MenuAnswer, ticket: Ticket, queue: TicketQueue, log: EventLog
  ) -> MenuAnswerEffect {
    guard MenuAnswer.offered(for: ticket.summary).contains(answer) else {
      log.write("answered from the menu: \(answer.rawValue), not offered for this request")
      return .ignored
    }
    log.write("answered from the menu: \(answer.rawValue)")
    if let outcome = answer.outcome {
      return .finish(outcome)
    }
    do {
      let moved = try queue.showNow(
        ticket, isOnScreen: { QueueHandoffChannel(ticket: $0).shownDisplayID() != nil })
      switch moved.place {
      case .front: log.write("show now: moved to the front")
      case .behindShownPanel: log.write("show now: next after the panel on screen")
      }
      return .moved(moved)
    } catch {
      log.write("show now: failed to move: \(error)")
      return .ignored
    }
  }

  static func recordDecision(
    request: ApprovalRequest, answer: DecisionAnswer, history: DecisionHistory, log: EventLog
  ) {
    do {
      try history.append(DecisionHistoryEntry(request: request, answer: answer))
    } catch {
      log.write("history: failed to record: \(error)")
    }
  }

  static func writeReply(_ outcome: ApprovalOutcome, host: ApprovalCore.Host) {
    guard let data = host.encode(outcome) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func handBack(
    host: ApprovalCore.Host, log: EventLog, waiting: WaitingHandBack
  ) -> Never {
    writeReply(.noDecision, host: host)
    log.write(TimeoutHandBack.logLine(for: host))
    waiting.record()
    exit(0)
  }

  private static func describe(_ error: Error) -> String {
    guard let adapterError = error as? AdapterError else { return String(describing: error) }
    switch adapterError {
    case .malformedInput(let reason): return reason
    }
  }

  static func describe(_ outcome: ApprovalOutcome) -> String {
    switch outcome {
    case .noDecision: return "no decision"
    case .addContext: return "context note"
    case .allow(_, let updatedPermissions):
      return updatedPermissions.isEmpty ? "allow" : "allow+permissions"
    case .deny(_, let interrupt): return interrupt ? "deny+interrupt" : "deny"
    }
  }
}

@MainActor
private final class DisplayWatch: NSObject {
  private enum State {
    case queued
    case waitingForIdle
    case shown(controller: PanelController)
    case showingResult(card: TestPanelResultCard)
  }

  private struct PendingHandoff {
    let handoff: QueueHandoff
    let controller: PanelController
  }

  private struct PreparedPanel {
    let controller: PanelController
    let backdrop: BackdropWindow
    let displayID: UInt32
    let screenLayouts: [ScreenLayout]
  }

  private let app: PanelApplication
  private let request: ApprovalRequest
  private let host: ApprovalCore.Host
  private let mode: PanelRunMode
  private let queue: TicketQueue
  private var ticket: Ticket
  private var showsWithoutIdle: Bool
  private let log: EventLog
  private let activityGate: ActivityGate
  private let quietState: QuietState
  private let settings: Settings
  private let systemActivity = SystemActivity()
  private let abandonReason: () -> String?
  private let handBackIsDue: () -> Bool
  private let sessionsDirectory: URL
  private let history: DecisionHistory
  private let hostApp: HostApp?
  private let checkpoint: ContextCheckpointSession?
  private let waitingHandBack: WaitingHandBack
  private let cardSlots: WaitingStore
  private let isPaused: () -> Bool
  private var waitingForIdleSince = ProcessInfo.processInfo.systemUptime
  private var waitFollowsStepAside = false
  private var approvalCard: CornerCard?
  private var approvalCardStage = ApprovalCardStage.notShown
  private var approvalClaim: ApprovalClaim?
  private var checkpointChoice: ContextCheckpointChoice?
  private var lease: DisplayLease?
  private var state: State
  private var lastWaitingEntries: [WaitingEntry]
  private var handoffListener: QueueHandoffListener?
  private var pendingHandoff: PendingHandoff?
  private var preparedPanel: PreparedPanel?
  private var preparation: QueueHandoffPreparation?
  private var shownDisplay: QueueShownDisplay?
  private var screenObserver: (any NSObjectProtocol)?
  private var handoffPoll: Timer?
  private var hasEvaluatedChatTracking = false
  private var chatTrackingDrift: ChatTrackingDrift?
  private let subagentChain: [SubagentChainLink]?

  init(
    app: PanelApplication, request: ApprovalRequest, mode: PanelRunMode, queue: TicketQueue,
    ticket: Ticket, lease: DisplayLease?, log: EventLog, activityGate: ActivityGate,
    quietState: QuietState, settings: Settings, subagentChain: [SubagentChainLink]?,
    waitingEntries: [WaitingEntry], sessionsDirectory: URL, history: DecisionHistory,
    hostApp: HostApp?,
    checkpoint: ContextCheckpointSession?, showsWithoutIdle: Bool,
    waitingHandBack: WaitingHandBack, cardSlots: WaitingStore,
    abandonReason: @escaping () -> String?, handBackIsDue: @escaping () -> Bool,
    isPaused: @escaping () -> Bool
  ) {
    self.app = app
    self.request = request
    self.host = request.host
    self.mode = mode
    self.queue = queue
    self.ticket = ticket
    self.showsWithoutIdle = showsWithoutIdle
    self.lease = lease
    self.log = log
    self.activityGate = activityGate
    self.quietState = quietState
    self.settings = settings
    self.subagentChain = subagentChain
    self.lastWaitingEntries = waitingEntries
    self.sessionsDirectory = sessionsDirectory
    self.history = history
    self.hostApp = hostApp
    self.checkpoint = checkpoint
    self.waitingHandBack = waitingHandBack
    self.cardSlots = cardSlots
    self.abandonReason = abandonReason
    self.handBackIsDue = handBackIsDue
    self.isPaused = isPaused
    self.state = lease == nil ? .queued : .waitingForIdle
    super.init()
    observeScreenChanges()
    if lease == nil {
      log.write("next in line")
      app.afterLaunch { [weak self] in self?.startWarmStandby() }
    } else if mode.waitsForIdleOnArrival {
      log.write("waiting for idle")
    } else {
      log.write("showing at once")
      app.afterLaunch { [weak self] in self?.showOnArrival() }
    }
  }

  @objc func tick() {
    if let reason = abandonReason() {
      abandon(reason)
    }
    if handBackIsDue() {
      handBack()
    }
    if anotherRequestWaits() {
      yieldToAnotherRequest()
    }
    takeMenuAnswer()

    switch state {
    case .queued:
      takeDisplayIfFree()
      followHeadDisplay()

    case .waitingForIdle:
      if queue.isOvertakenFromMenu(ticket) {
        giveWayToRequestShownFromMenu()
        return
      }
      let quiet = quietTimeHoldsPanels()
      if quiet {
        holdApprovalCardForQuietTime()
      }
      if !quiet,
        showsWithoutIdle
          || activityGate.isIdle(
            secondsSinceLastInput: systemActivity.secondsSinceLastInput(),
            modifiersHeld: systemActivity.modifiersHeld())
      {
        showAfterIdle()
        return
      }
      showApprovalCardIfDue(quiet: quiet)

    case .shown(let controller):
      if quietTimeHoldsPanels() {
        closeShownPanel(controller)
        log.write("stepped aside: quiet time")
        waitForIdle(afterStepAside: false)
        return
      }
      let waitingEntries = queue.waitingEntries(excluding: ticket)
      if waitingEntries != lastWaitingEntries {
        lastWaitingEntries = waitingEntries
        controller.setWaitingEntries(waitingEntries)
      }

    case .showingResult:
      break
    }
  }

  private func quietTimeHoldsPanels() -> Bool {
    mode.honorsQuietTime && quietState.activeUntil() != nil
  }

  private func waitForIdle(afterStepAside: Bool) {
    state = .waitingForIdle
    waitingForIdleSince = ProcessInfo.processInfo.systemUptime
    waitFollowsStepAside = afterStepAside
    log.write("waiting for idle")
  }

  private func showApprovalCardIfDue(quiet: Bool) {
    guard
      ApprovalCardTiming.shouldShow(
        enabled: settings.approvalCard, mode: mode,
        secondsWaiting: ProcessInfo.processInfo.systemUptime - waitingForIdleSince,
        delay: ApprovalCardTiming.delay(
          afterStepAside: waitFollowsStepAside, configured: settings.approvalCardDelay),
        quiet: quiet, paused: isPaused(), stage: approvalCardStage)
    else { return }
    guard
      let card = CornerCard.inFreeSlot(
        of: cardSlots,
        model: .approval(hostName: host.displayName, projectName: request.projectName),
        accessibilityTitle: "Countersign approval", appearance: settings.appearance,
        onAction: { [weak self] in self?.showFromApprovalCard() },
        onDismiss: { [weak self] in self?.dismissApprovalCard() })
    else {
      claimApprovalSlot()
      return
    }
    withdrawApprovalClaim()
    approvalCard = card
    approvalCardStage = .shown
    card.show()
    log.write("approval card: shown")
  }

  private func claimApprovalSlot() {
    guard approvalClaim == nil else { return }
    let claim = ApprovalClaim.current()
    approvalClaim = claim
    log.write("approval card: waiting for a slot")
    do {
      try cardSlots.writeApprovalClaim(claim)
    } catch {
      log.write("approval card: failed to claim a slot: \(error)")
    }
  }

  private func withdrawApprovalClaim() {
    guard let approvalClaim else { return }
    cardSlots.removeApprovalClaim(approvalClaim)
    self.approvalClaim = nil
  }

  private func holdApprovalCardForQuietTime() {
    waitingForIdleSince = ProcessInfo.processInfo.systemUptime
    waitFollowsStepAside = false
    guard approvalCard != nil else { return }
    closeApprovalCard()
    approvalCardStage = approvalCardStage.afterQuietTime
    log.write("approval card: closed for quiet time")
  }

  private func showFromApprovalCard() {
    guard case .waitingForIdle = state else { return }
    closeApprovalCard()
    showsWithoutIdle = true
    log.write("approval card: show")
  }

  private func dismissApprovalCard() {
    closeApprovalCard()
    approvalCardStage = .dismissed
    log.write("approval card: dismissed")
  }

  private func closeApprovalCard() {
    withdrawApprovalClaim()
    approvalCard?.close()
    approvalCard = nil
  }

  private func takeMenuAnswer() {
    let isShown: Bool
    switch state {
    case .queued, .waitingForIdle: isShown = false
    case .shown: isShown = true
    case .showingResult: return
    }
    guard let answer = queue.takeMenuAnswer(for: ticket) else { return }
    if answer == .show, isShown {
      log.write("answered from the menu: show, already on screen")
      return
    }
    switch HookRunner.receiveMenuAnswer(answer, ticket: ticket, queue: queue, log: log) {
    case .finish(let outcome):
      if case .queued = state {
        discardHandoff()
        discardPreparedPanel("answered from the menu")
      }
      finish(outcome)
    case .moved(let moved):
      ticket = moved.ticket
      showsWithoutIdle = moved.place == .front
    case .ignored:
      break
    }
  }

  private func giveWayToRequestShownFromMenu() {
    closeApprovalCard()
    lease?.release()
    lease = nil
    state = .queued
    log.write("gave way to a request shown from the menu")
    startWarmStandby()
  }

  private func makeController(handoffBackdrop: BackdropWindow?, afterHandoff: Bool)
    -> PanelController
  {
    if mode.followsChat, !hasEvaluatedChatTracking {
      hasEvaluatedChatTracking = true
      chatTrackingDrift = ChatTrackingHealth.evaluate(
        request: request, sessionsDirectory: sessionsDirectory)
      if let chatTrackingDrift {
        log.write("chat tracking: \(chatTrackingDrift.reason)")
      }
    }
    let waitingEntries = queue.waitingEntries(excluding: ticket)
    lastWaitingEntries = waitingEntries
    return PanelController(
      request: request, waitingEntries: waitingEntries,
      armDuration: afterHandoff ? settings.chainedArmDelay : settings.armDelay,
      snoozePresets: settings.snoozePresets, questionNotes: settings.questionNotes,
      modeAfterPlan: settings.modeAfterPlan, panelSound: settings.panelSound,
      appearance: settings.appearance, accentColor: settings.accentColor,
      chatTrackingDrift: chatTrackingDrift, subagentChain: subagentChain,
      isTestPanel: mode.isTest, handoffBackdrop: handoffBackdrop, afterHandoff: afterHandoff,
      onFinish: { [weak self] outcome in self?.finish(outcome) },
      onSnooze: { [weak self] seconds in self?.handleSnooze(seconds) },
      onStepAside: { [weak self] reason in self?.handleStepAside(reason) },
      sessionIdle: checkpoint?.isIdle() ?? false,
      onCheckpointChoice: checkpoint == nil && !mode.isTest
        ? nil : { [weak self] choice in self?.handleCheckpointChoice(choice) })
  }

  private var isCheckpoint: Bool {
    guard case .contextCheckpoint = request.kind else { return false }
    return true
  }

  private func handleCheckpointChoice(_ choice: ContextCheckpointChoice) {
    checkpointChoice = choice
    guard !mode.isTest else { return }
    log.write("context choice: \(choice.rawValue)")
    if choice == .notThisSession {
      checkpoint?.mute()
    }
  }

  private func showAfterIdle() {
    closeApprovalCard()
    handOffIfAskingAppIsFrontmost()
    let controller = makeController(handoffBackdrop: nil, afterHandoff: false)
    app.show(controller)
    publishShownDisplay(of: controller)
    log.write("displayed")
    showsWithoutIdle = false
    state = .shown(controller: controller)
  }

  private func showOnArrival() {
    guard case .waitingForIdle = state else { return }
    if anotherRequestWaits() {
      yieldToAnotherRequest()
    }
    showAfterIdle()
  }

  private func anotherRequestWaits() -> Bool {
    mode.yieldsToOtherRequests && queue.realRequestCount(excluding: ticket) > 0
  }

  private func yieldToAnotherRequest() -> Never {
    switch state {
    case .shown(let controller):
      closeShownPanel(controller)
    case .showingResult(let card):
      card.close()
    case .waitingForIdle:
      closeApprovalCard()
    case .queued:
      break
    }
    queue.remove(ticket)
    lease?.release()
    log.write(TestPanelLog.closedForRealRequest)
    exit(0)
  }

  private func showAfterHandoff(_ handedOff: PendingHandoff) {
    let waitingEntries = queue.waitingEntries(excluding: ticket)
    lastWaitingEntries = waitingEntries
    handedOff.controller.setWaitingEntries(waitingEntries)
    app.show(handedOff.controller)
    publishShownDisplay(of: handedOff.controller)
    let milliseconds =
      (ProcessInfo.processInfo.systemUptime - handedOff.handoff.receivedAt) * 1000
    log.write("displayed after queue handoff in \(String(format: "%.1f", milliseconds)) ms")
    showsWithoutIdle = false
    state = .shown(controller: handedOff.controller)
  }

  private func publishShownDisplay(of controller: PanelController) {
    if shownDisplay == nil {
      shownDisplay = QueueHandoffChannel(ticket: ticket).publishShownDisplay()
    }
    shownDisplay?.publish(displayID: controller.displayID)
  }

  private func closeShownPanel(_ controller: PanelController) {
    controller.close()
    shownDisplay?.clear()
  }

  private func handOffIfAskingAppIsFrontmost() {
    guard !mode.isTest, mode.usesHandoffApps else { return }
    let frontmostApp = NSWorkspace.shared.frontmostApplication
    guard let frontmostBundleID = frontmostApp?.bundleIdentifier,
      HandoffCheck.shouldHandOff(
        frontmostBundleID: frontmostBundleID, frontmostPID: frontmostApp?.processIdentifier,
        handoffApps: settings.handoffApps, hostAppPID: hostApp?.processIdentifier)
    else { return }
    log.write("handoff: \(frontmostBundleID) frontmost")
    if let outcome = host.handoffOutcome {
      HookRunner.writeReply(outcome, host: host)
    }
    closeApprovalCard()
    discardHandoff()
    discardPreparedPanel("handed off")
    queue.remove(ticket)
    lease?.release()
    waitingHandBack.record()
    exit(0)
  }

  private func abandon(_ reason: String) -> Never {
    let wording: String
    switch state {
    case .queued:
      discardHandoff()
      discardPreparedPanel("resolved")
      wording = "resolved while queued"
    case .waitingForIdle:
      closeApprovalCard()
      wording = "resolved while waiting for idle"
    case .shown(let controller):
      closeShownPanel(controller)
      wording = "resolved while displayed"
    case .showingResult(let card):
      card.close()
      wording = "resolved while showing the result"
    }
    queue.remove(ticket)
    lease?.release()
    log.write("\(wording): \(reason)")
    if !mode.isTest, reason != "paused" {
      HookRunner.recordDecision(
        request: request, answer: .resolvedElsewhere, history: history, log: log)
    }
    exit(0)
  }

  private func handBack() -> Never {
    HookRunner.writeReply(.noDecision, host: host)
    log.write(TimeoutHandBack.logLine(for: host))
    switch state {
    case .queued:
      discardHandoff()
      discardPreparedPanel("handed back")
    case .waitingForIdle:
      closeApprovalCard()
    case .showingResult:
      break
    case .shown(let controller):
      handOffToNextInLine(from: controller)
      closeShownPanel(controller)
    }
    queue.remove(ticket)
    lease?.release()
    waitingHandBack.record()
    exit(0)
  }

  private func finish(_ outcome: ApprovalOutcome) {
    switch mode {
    case .hook:
      HookRunner.writeReply(outcome, host: host)
      log.write("outcome: \(HookRunner.describe(outcome))")
    case .checkpoint:
      HookRunner.writeReply(outcome, host: host)
      log.write("outcome: context \(checkpointChoice?.rawValue ?? "dismissed")")
    case .test(let kind):
      log.write(TestPanelLog.outcome(outcome, kind: kind))
    }
    if !mode.isTest {
      HookRunner.recordDecision(
        request: request,
        answer: DecisionAnswer.answer(
          for: outcome, checkpointChoice: checkpointChoice, isCheckpoint: isCheckpoint),
        history: history, log: log)
    }
    closeApprovalCard()
    var panelFrame: NSRect?
    if case .shown(let controller) = state {
      panelFrame = controller.frame
      handOffToNextInLine(from: controller)
      closeShownPanel(controller)
    }
    queue.remove(ticket)
    lease?.release()
    lease = nil
    if outcome == .noDecision {
      waitingHandBack.record()
    }
    guard case .test(let kind) = mode, let panelFrame else { exit(0) }
    showResult(of: outcome, kind: kind, around: panelFrame)
  }

  private func showResult(of outcome: ApprovalOutcome, kind: TestPanelKind, around frame: NSRect) {
    let result = TestPanelResult.describe(outcome, kind: kind, checkpointChoice: checkpointChoice)
    let card = TestPanelResultCard(
      title: result.title, detail: result.detail, around: frame, appearance: settings.appearance,
      onClose: { exit(0) })
    state = .showingResult(card: card)
    card.show()
    log.write(TestPanelLog.resultShown)
  }

  private func handOffToNextInLine(from controller: PanelController) {
    guard let successor = queue.nextInLine(after: ticket) else { return }
    let channel = QueueHandoffChannel(ticket: successor)
    let reply = channel.request(state: QueueHandoff.state(displayID: controller.displayID))
    if reply.waitedForPreparation {
      log.write("queue handoff: next in line still preparing")
    }
    guard let elapsed = reply.elapsed else {
      log.write("queue handoff: no reply")
      return
    }
    let milliseconds =
      Double(elapsed.components.attoseconds) / 1e15
      + Double(elapsed.components.seconds) * 1000
    log.write("queue handoff: ready in \(String(format: "%.1f", milliseconds)) ms")
  }

  private func startWarmStandby() {
    guard case .queued = state else { return }
    preparation = QueueHandoffChannel(ticket: ticket).publishPreparation()
    listenForHandoff()
    preparePanel()
  }

  private func listenForHandoff() {
    guard case .queued = state, handoffListener == nil else { return }
    handoffListener = QueueHandoffChannel(ticket: ticket).listen(on: .main) { [weak self] state in
      MainActor.assumeIsolated { self?.receiveHandoff(state: state) }
    }
  }

  private func observeScreenChanges() {
    guard screenObserver == nil else { return }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.followScreenChange() }
    }
  }

  private func followScreenChange() {
    switch state {
    case .queued:
      prepareAgainForNewScreens()
    case .waitingForIdle:
      approvalCard?.followScreenChange()
    case .shown(let controller):
      controller.followScreenChange()
      publishShownDisplay(of: controller)
    case .showingResult(let card):
      card.followScreenChange()
    }
  }

  private func preparePanel() {
    guard case .queued = state, pendingHandoff == nil, preparedPanel == nil,
      let screen = headScreen() ?? PanelController.resolveTargetScreen(),
      let displayID = screen.displayID
    else { return }
    preparation?.begin()
    let startedAt = ProcessInfo.processInfo.systemUptime
    let screenLayouts = ScreenLayout.current()
    let backdrop = BackdropWindow(screen: screen)
    let controller = makeController(handoffBackdrop: backdrop, afterHandoff: true)
    controller.layOut()
    preparedPanel = PreparedPanel(
      controller: controller, backdrop: backdrop, displayID: displayID,
      screenLayouts: screenLayouts)
    let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1000
    preparation?.end()
    log.write("next in line: panel prepared in \(String(format: "%.1f", milliseconds)) ms")
  }

  private func headScreen() -> NSScreen? {
    guard let ahead = queue.ticketAhead(of: ticket),
      let displayID = QueueHandoffChannel(ticket: ahead).shownDisplayID()
    else { return nil }
    return NSScreen.screen(displayID: displayID)
  }

  private func followHeadDisplay() {
    guard case .queued = state, pendingHandoff == nil, let prepared = preparedPanel,
      let headDisplayID = headScreen()?.displayID, headDisplayID != prepared.displayID
    else { return }
    discardPreparedPanel("display changed")
    preparePanel()
  }

  private func prepareAgainForNewScreens() {
    guard case .queued = state, pendingHandoff == nil, preparedPanel != nil else { return }
    discardPreparedPanel("screens changed")
    preparePanel()
  }

  private func fileContextChanged(since prepared: PreparedPanel?) -> Bool {
    preparation?.begin()
    defer { preparation?.end() }
    return FileDiffBuilder.load(for: request) != prepared?.controller.fileDiffs
  }

  private func discardPreparedPanel(_ reason: String) {
    guard let discarded = preparedPanel else { return }
    preparedPanel = nil
    discarded.controller.close()
    log.write("prepared panel discarded: \(reason)")
  }

  private func receiveHandoff(state handoffState: UInt64) {
    guard case .queued = state, pendingHandoff == nil else { return }
    let handoff = QueueHandoff(
      receivedAt: ProcessInfo.processInfo.systemUptime, state: handoffState)
    let screen =
      handoff.displayID.flatMap { NSScreen.screen(displayID: $0) }
      ?? PanelController.resolveTargetScreen()
    let prepared = preparedPanel
    preparedPanel = nil
    let decision = PreparedPanelReuse.decide(
      preparedDisplayID: prepared?.displayID, targetDisplayID: screen?.displayID,
      screensChanged: prepared.map { $0.screenLayouts != ScreenLayout.current() } ?? false,
      fileContextChanged: { fileContextChanged(since: prepared) })
    let controller: PanelController
    if case .reuse = decision, let prepared {
      prepared.backdrop.showAtFullOpacity()
      QueueHandoffChannel(ticket: ticket).signalReady()
      log.write("queue handoff received")
      log.write("queue handoff: prepared panel reused")
      controller = prepared.controller
    } else {
      prepared?.controller.close()
      let backdrop = screen.map { BackdropWindow(screen: $0) }
      backdrop?.showAtFullOpacity()
      QueueHandoffChannel(ticket: ticket).signalReady()
      log.write("queue handoff received")
      if case .rebuild(let reason) = decision {
        log.write("queue handoff: prepared panel rebuilt (\(reason.rawValue))")
      }
      controller = makeController(handoffBackdrop: backdrop, afterHandoff: true)
      controller.layOut()
    }
    pendingHandoff = PendingHandoff(handoff: handoff, controller: controller)
    let poll = Timer(
      timeInterval: 0.01, target: self, selector: #selector(pollAfterHandoff), userInfo: nil,
      repeats: true)
    RunLoop.main.add(poll, forMode: .common)
    handoffPoll = poll
    takeDisplayIfFree()
  }

  @objc private func pollAfterHandoff() {
    takeDisplayIfFree()
  }

  private func takeDisplayIfFree() {
    guard case .queued = state else { return }
    guard let acquired = queue.acquireDisplayIfHead(ticket) else {
      if let pendingHandoff,
        !pendingHandoff.handoff.isFresh(at: ProcessInfo.processInfo.systemUptime)
      {
        log.write("queue handoff: stale")
        discardHandoff()
      }
      return
    }
    lease = acquired
    handoffListener?.cancel()
    handoffListener = nil
    preparation?.cancel()
    preparation = nil
    guard let handedOff = pendingHandoff,
      handedOff.handoff.isFresh(at: ProcessInfo.processInfo.systemUptime),
      !quietTimeHoldsPanels()
    else {
      discardHandoff()
      discardPreparedPanel("no handoff")
      waitForIdle(afterStepAside: false)
      return
    }
    if let reason = abandonReason() {
      abandon(reason)
    }
    handOffIfAskingAppIsFrontmost()
    pendingHandoff = nil
    stopHandoffPoll()
    showAfterHandoff(handedOff)
  }

  private func discardHandoff() {
    pendingHandoff?.controller.close()
    pendingHandoff = nil
    stopHandoffPoll()
  }

  private func stopHandoffPoll() {
    handoffPoll?.invalidate()
    handoffPoll = nil
  }

  private func handleSnooze(_ seconds: TimeInterval) {
    if mode.isTest {
      endTestPanelOnSnooze(seconds)
    }
    let until = Date().addingTimeInterval(seconds)
    do {
      try quietState.quietTime.quiet(until: until)
    } catch {
      log.write("failed to set quiet time: \(error)")
      return
    }
    guard case .shown(let controller) = state else { return }
    closeShownPanel(controller)
    log.write("quiet time until \(Self.formattedTime(until)) (\(DurationText.describe(seconds)))")
    waitForIdle(afterStepAside: false)
  }

  private func endTestPanelOnSnooze(_ seconds: TimeInterval) -> Never {
    log.write(TestPanelLog.snooze(seconds: seconds))
    if case .shown(let controller) = state {
      closeShownPanel(controller)
    }
    queue.remove(ticket)
    lease?.release()
    exit(0)
  }

  private func handleStepAside(_ reason: StepAsideReason) {
    guard case .shown(let controller) = state else { return }
    closeShownPanel(controller)
    log.write("stepped aside: \(reason.rawValue)")
    approvalCardStage = approvalCardStage.afterStepAside
    waitForIdle(afterStepAside: true)
  }

  private static func formattedTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
  }
}

private struct ScreenLayout: Equatable {
  let displayID: UInt32?
  let frame: NSRect
  let visibleFrame: NSRect
  let backingScaleFactor: CGFloat

  @MainActor
  static func current() -> [ScreenLayout] {
    NSScreen.screens.map { screen in
      ScreenLayout(
        displayID: screen.displayID, frame: screen.frame, visibleFrame: screen.visibleFrame,
        backingScaleFactor: screen.backingScaleFactor)
    }
  }
}
