import AppKit
import ApprovalCore

@MainActor
enum MenuBarCompanion {
  static func run() -> Never {
    let paths = AppPaths.standard
    let log = EventLog(file: paths.logFile)
    log.rotateIfNeeded()

    let instanceLock: ExclusiveFileLock
    do {
      guard let acquired = try ExclusiveFileLock.acquire(paths.companionLockFile) else {
        let asksForSetup = CommandLine.arguments.contains(CompanionLaunch.setupArgument)
        DistributedNotificationCenter.default().postNotificationName(
          asksForSetup
            ? CompanionController.openSetupNotification
            : CompanionController.openSettingsNotification,
          object: nil, userInfo: nil, deliverImmediately: true)
        log.write(
          asksForSetup
            ? "companion: already running, asked it to open setup"
            : "companion: already running, asked it to open Settings")
        exit(0)
      }
      instanceLock = acquired
    } catch {
      log.write("companion: could not open companion.lock: \(error), exiting")
      exit(0)
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let controller = CompanionController(paths: paths, log: log, instanceLock: instanceLock)
    application.delegate = controller
    withExtendedLifetime(controller) {
      application.run()
    }
    exit(0)
  }
}

@MainActor
private final class CompanionController: NSObject, NSApplicationDelegate, NSMenuDelegate {
  static let openSettingsNotification = Notification.Name(
    CompanionLaunch.openSettingsNotificationName)
  static let openSetupNotification = Notification.Name(
    CompanionLaunch.openSetupNotificationName)
  private static let refreshInterval: TimeInterval = 2
  private static let updateCheckInterval: TimeInterval = 3600

  private let paths: AppPaths
  private let log: EventLog
  private var instanceLock: ExclusiveFileLock
  private let pauseSwitch: PauseSwitch
  private let quietTime: QuietTime
  private let stateSwitches: StateSwitches
  private let queue: TicketQueue
  private var statusItem: NSStatusItem?
  private var refreshTimer: Timer?
  private var updateCheckTimer: Timer?
  private var shownIcon: CompanionIcon?
  private var menuActions: [CompanionMenuAction] = []
  private var isLaunchAtLoginUnavailable = false
  private var lastConfigLogLines: [String] = []
  private var updateCheckState: UpdateCheckState?
  private var manualCheckResult: ManualUpdateCheckResult?
  private var updateCheckRequests = UpdateCheckRequests()
  private var settingsWindow: SettingsWindowController?
  private var setupWindow: SetupWindowController?
  private var pendingQuit: QuitOutcome?
  private var isMenuOpen = false
  private var reportedCopyRefreshFailures: Set<String> = []

  init(paths: AppPaths, log: EventLog, instanceLock: ExclusiveFileLock) {
    self.paths = paths
    self.log = log
    self.instanceLock = instanceLock
    pauseSwitch = PauseSwitch(file: paths.pauseFile)
    quietTime = QuietTime(file: paths.quietFile)
    stateSwitches = StateSwitches(pauseSwitch: pauseSwitch, quietTime: quietTime)
    queue = TicketQueue(directory: paths.queueDirectory, lockFile: paths.displayLockFile)
    super.init()
    reloadUpdateCheckState()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let launchEvent = NSAppleEventManager.shared().currentAppleEvent
    let opensSettings = CompanionLaunch.opensSettings(
      launchEventID: launchEvent?.eventID,
      launchedAs: launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue)
    if refreshApplicationsCopy(opensSettingsAfter: opensSettings) { return }
    finishLaunching(opensSettings: opensSettings)
  }

  private func finishLaunching(opensSettings launchOpensSettings: Bool) {
    resumePauseSetAtQuit()
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = self
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.menu = menu
    statusItem = item
    refreshIcon()
    let timer = Timer(
      timeInterval: Self.refreshInterval, target: self, selector: #selector(refreshTimerFired),
      userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)
    refreshTimer = timer
    let updateTimer = Timer(
      timeInterval: Self.updateCheckInterval, target: self,
      selector: #selector(updateCheckTimerFired), userInfo: nil, repeats: true)
    RunLoop.main.add(updateTimer, forMode: .common)
    updateCheckTimer = updateTimer
    performScheduledUpdateCheckIfNeeded()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(openSettingsRequested(_:)), name: Self.openSettingsNotification,
      object: nil, suspensionBehavior: .deliverImmediately)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(openSetupRequested(_:)), name: Self.openSetupNotification,
      object: nil, suspensionBehavior: .deliverImmediately)
    let opensSettingsForUpgrade = opensSettingsAfterUpgrade()
    let relaunch = takeFreshCopyRefreshRelaunch()
    if opensSettingsForUpgrade { return }
    if let relaunch {
      if relaunch.opensSettings { openSetupOrSettings() }
      return
    }
    guard launchOpensSettings else {
      log.write("companion: started at login")
      return
    }
    openSetupOrSettings()
  }

  private var opensSetupAtLaunch: Bool {
    CommandLine.arguments.contains(CompanionLaunch.setupArgument)
      || SetupLaunch.opensSetup(
        setupShown: FileManager.default.fileExists(atPath: paths.setupShownFile.path),
        tourShown: FileManager.default.fileExists(atPath: paths.tourShownFile.path))
  }

  private func openSetupOrSettings() {
    if opensSetupAtLaunch {
      log.write("companion: started, opening setup")
      openSetup()
      return
    }
    log.write("companion: started")
    openSettings()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    if refreshApplicationsCopy(opensSettingsAfter: true) { return false }
    log.write("companion: reopened, opening settings")
    openSettings()
    return false
  }

  @objc nonisolated private func openSettingsRequested(_ notification: Notification) {
    Task { @MainActor [weak self] in
      self?.log.write("companion: another launch asked to open settings")
      self?.openSettings()
    }
  }

  @objc nonisolated private func openSetupRequested(_ notification: Notification) {
    Task { @MainActor [weak self] in
      self?.log.write("companion: another launch asked to open setup")
      self?.openSetup()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    settingsWindow?.model.commitEditing()
    if let pendingQuit {
      apply(pendingQuit)
    }
    log.write("companion: quit")
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    reloadUpdateCheckState()
    menu.removeAllItems()
    menuActions = []
    for item in CompanionMenu.items(for: currentInput()) {
      menu.addItem(makeMenuItem(item))
    }
    refreshIcon()
  }

  func menuWillOpen(_ menu: NSMenu) {
    isMenuOpen = true
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
    manualCheckResult = nil
  }

  @objc private func refreshTimerFired() {
    refreshIcon()
  }

  @objc private func updateCheckTimerFired() {
    if refreshApplicationsCopy(opensSettingsAfter: false) { return }
    performScheduledUpdateCheckIfNeeded()
  }

  private var isAnythingOnScreen: Bool {
    if let settingsWindow, !settingsWindow.isClosed { return true }
    if setupWindow?.window?.isVisible == true { return true }
    return TestPanelLauncher.shared.isRunning || NSApplication.shared.modalWindow != nil
      || isMenuOpen
  }

  private func refreshApplicationsCopy(opensSettingsAfter: Bool) -> Bool {
    guard !isAnythingOnScreen,
      let refresh = AppBundleCopy.refresh(
        runningBundle: Bundle.main.bundlePath,
        home: FileManager.default.homeDirectoryForCurrentUser, fileSystem: .local)
    else { return false }
    let change = "~/Applications/Countersign.app from \(refresh.from) to \(refresh.to)"
    do {
      try AppBundleCopy.perform(source: refresh.source, destination: refresh.destination)
    } catch {
      if reportedCopyRefreshFailures.insert(refresh.to).inserted {
        log.write("companion: could not refresh \(change): \(error)")
      }
      return false
    }
    do {
      try CopyRefreshRelaunch.write(
        CopyRefreshRelaunch(opensSettings: opensSettingsAfter, writtenAt: Date()),
        to: paths.copyRefreshRelaunchFile)
    } catch {
      log.write("companion: refreshed \(change), not relaunching: \(error)")
      return false
    }
    log.write("companion: refreshed \(change), relaunching")
    instanceLock.release()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.addsToRecentItems = false
    configuration.activates = opensSettingsAfter
    NSWorkspace.shared.openApplication(at: refresh.destination, configuration: configuration) {
      @Sendable [weak self] _, error in
      let failure = error.map { String(describing: $0) }
      Task { @MainActor in
        self?.finishRelaunch(failure: failure, opensSettingsAfter: opensSettingsAfter)
      }
    }
    return true
  }

  private func finishRelaunch(failure: String?, opensSettingsAfter: Bool) {
    guard let failure else {
      NSApplication.shared.terminate(nil)
      return
    }
    log.write("companion: could not relaunch ~/Applications/Countersign.app: \(failure)")
    try? FileManager.default.removeItem(at: paths.copyRefreshRelaunchFile)
    do {
      guard let reacquired = try ExclusiveFileLock.acquire(paths.companionLockFile) else {
        log.write("companion: another instance holds companion.lock, quitting")
        NSApplication.shared.terminate(nil)
        return
      }
      instanceLock = reacquired
    } catch {
      log.write("companion: could not open companion.lock again: \(error)")
    }
    if statusItem == nil {
      finishLaunching(opensSettings: opensSettingsAfter)
    } else if opensSettingsAfter {
      openSettings()
    }
  }

  private func takeFreshCopyRefreshRelaunch() -> CopyRefreshRelaunch? {
    let file = paths.copyRefreshRelaunchFile
    let marker = CopyRefreshRelaunch.read(file)
    try? FileManager.default.removeItem(at: file)
    guard let marker, marker.isFresh(now: Date()) else { return nil }
    log.write("companion: relaunched after refreshing the copy")
    return marker
  }

  @objc private func menuItemChosen(_ sender: NSMenuItem) {
    guard menuActions.indices.contains(sender.tag) else { return }
    handle(menuActions[sender.tag])
    refreshIcon()
  }

  private func refreshIcon() {
    let icon = CompanionMenu.icon(
      isPaused: pauseSwitch.isPaused, quietUntil: QuietState(paths: paths).activeUntil())
    guard icon != shownIcon, let button = statusItem?.button else { return }
    button.image = MenuBarIcon.image(for: icon)
    shownIcon = icon
  }

  private func currentInput() -> CompanionMenuInput {
    let configFile = loadConfigFile()
    let checkpointSettings = Settings.resolve(file: configFile, host: .claude).contextCheckpoints
    let contextRows =
      checkpointSettings.enabled && checkpointSettings.menuBarMeter
      ? ContextMeter.rows(
        store: ContextCheckpointStore(directory: paths.contextCheckpointsDirectory),
        isLive: {
          ContextMeter.isLive(sessionID: $0, sessionsDirectory: paths.claudeSessionsDirectory)
        })
      : []
    return CompanionMenuInput(
      isPaused: pauseSwitch.isPaused,
      quietUntil: QuietState(paths: paths, schedule: configFile.quietSchedule).activeUntil(),
      pendingEntries: queue.waitingEntries(),
      snoozePresets: CompanionMenu.snoozePresets(for: configFile),
      launchAtLogin: launchAtLoginState(),
      updateAvailable: currentUpdateAvailability(),
      manualCheckResult: manualCheckResult,
      contextRows: contextRows,
      recentDecisions: DecisionHistory(paths: paths).recent(
        limit: CompanionMenu.recentDecisionLimit))
  }

  private func loadConfigFile() -> ConfigFile {
    let (configFile, configLogLines) = ConfigFileLoader.load(
      paths: paths, soundNames: SystemSounds.installedNames)
    if configLogLines != lastConfigLogLines {
      for line in configLogLines {
        log.write("config: \(line)")
      }
      lastConfigLogLines = configLogLines
    }
    return configFile
  }

  private func runningStablePath() -> String {
    guard let resolved = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
      return "(unresolved)"
    }
    return StableExecutablePath.stable(
      forResolved: resolved, home: FileManager.default.homeDirectoryForCurrentUser,
      isExecutable: FileManager.default.isExecutableFile(atPath:))
  }

  private func currentUpdateAvailability() -> UpdateAvailability? {
    guard case .newerAvailable(let version)? = updateCheckState?.outcome else { return nil }
    return UpdateAvailability(
      version: version,
      upgradeCommand: UpdateCommand.upgrade(forStablePath: runningStablePath()),
      releaseNotesURL: UpdateCommand.releaseNotesURL(version: version))
  }

  private func performScheduledUpdateCheckIfNeeded() {
    reloadUpdateCheckState()
    let configFile = loadConfigFile()
    guard configFile.checkForUpdates ?? Settings.defaultCheckForUpdates else { return }
    guard UpdateCheckSchedule.isDue(lastAttempt: updateCheckState?.lastAttempt, now: Date()) else {
      return
    }
    performUpdateCheck(manual: false)
  }

  private func reloadUpdateCheckState() {
    updateCheckState = UpdateCheckStateStore.load(file: paths.updateCheckFile)?
      .reevaluated(currentVersion: CountersignVersion.current)
  }

  private func performUpdateCheck(manual: Bool) {
    guard updateCheckRequests.begin(manual: manual) else { return }
    Task { [weak self] in
      guard let self else { return }
      let outcome = await UpdateFetcher.fetch(currentVersion: CountersignVersion.current)
      self.applyUpdateCheckResult(outcome, manual: manual)
    }
  }

  private func applyUpdateCheckResult(_ outcome: UpdateCheckOutcome, manual: Bool) {
    let answersWithAlert = updateCheckRequests.finish(manual: manual)
    let state = UpdateCheckState.recording(outcome, at: Date(), over: updateCheckState)
    if let state, state != updateCheckState {
      updateCheckState = state
      do {
        try UpdateCheckStateStore.save(state, to: paths.updateCheckFile)
      } catch {
        log.write("companion: failed to save update-check.json: \(error)")
      }
    }
    if case .unknown(let reason) = outcome {
      log.write("update check: \(reason)")
    }
    guard answersWithAlert else { return }
    switch outcome {
    case .newerAvailable:
      manualCheckResult = nil
    case .upToDate:
      manualCheckResult = .upToDate
    case .unknown:
      manualCheckResult = .failed
    }
    showUpdateCheckAlert(for: outcome)
  }

  private func showUpdateCheckAlert(for outcome: UpdateCheckOutcome) {
    let upgradeCommand = UpdateCommand.upgrade(forStablePath: runningStablePath())
    let releaseNotesURL: URL?
    if case .newerAvailable(let version) = outcome {
      releaseNotesURL = UpdateCommand.releaseNotesURL(version: version)
    } else {
      releaseNotesURL = nil
    }
    let answer = UpdateCheckAnswer.answer(
      for: outcome, currentVersion: CountersignVersion.current, upgradeCommand: upgradeCommand,
      releaseNotesURL: releaseNotesURL)
    switch UpdateCheckAlert.ask(for: answer) {
    case .copyUpgradeCommand(let command):
      copyToPasteboard(command)
    case .openReleaseNotes(let url):
      openInDefaultApp(url)
    case .ok, .later, nil:
      break
    }
  }

  private func launchAtLoginState() -> LaunchAtLoginState {
    guard !isLaunchAtLoginUnavailable else { return .unavailable }
    return LaunchAtLogin.state
  }

  private func makeMenuItem(_ item: CompanionMenuItem) -> NSMenuItem {
    switch item {
    case .separator:
      return .separator()
    case .entry(let entry):
      let menuItem = NSMenuItem(
        title: entry.title, action: nil, keyEquivalent: entry.keyEquivalent)
      menuItem.isEnabled = entry.isEnabled && isAvailableNow(entry.action)
      menuItem.state = entry.isChecked ? .on : .off
      if let action = entry.action {
        menuItem.tag = menuActions.count
        menuActions.append(action)
        menuItem.target = self
        menuItem.action = #selector(menuItemChosen(_:))
      }
      if !entry.submenu.isEmpty {
        let submenu = NSMenu(title: entry.title)
        submenu.autoenablesItems = false
        for child in entry.submenu {
          submenu.addItem(makeMenuItem(child))
        }
        menuItem.submenu = submenu
      }
      return menuItem
    }
  }

  private func isAvailableNow(_ action: CompanionMenuAction?) -> Bool {
    guard case .showTestPanel = action else { return true }
    return !TestPanelLauncher.shared.isRunning
  }

  private func handle(_ action: CompanionMenuAction) {
    switch action {
    case .pause:
      attempt("paused", failure: "failed to pause") { try stateSwitches.pause() }
    case .resume:
      attempt("resumed", failure: "failed to resume") { try pauseSwitch.resume() }
    case .snooze(let seconds):
      let until = Date().addingTimeInterval(seconds)
      attempt(
        "quiet time until \(TimeOfDayText.describe(until)) (\(DurationText.describe(seconds)))",
        failure: "failed to set quiet time"
      ) { try stateSwitches.snooze(until: until) }
    case .endQuietTime:
      attempt("quiet time ended", failure: "failed to end quiet time") {
        try QuietState(paths: paths).endNow()
      }
    case .openSettings:
      openSettings()
    case .showTestPanel(let kind):
      attempt("started a test panel (\(kind.rawValue))", failure: "failed to start a test panel") {
        try TestPanelLauncher.shared.launch(kind: kind) { refusal in
          TestPanelRefusalAlert.show(refusal: refusal)
        }
      }
    case .enableLaunchAtLogin:
      changeLaunchAtLogin("launch at login registered") { try LaunchAtLogin.register() }
    case .disableLaunchAtLogin:
      changeLaunchAtLogin("launch at login unregistered") { try LaunchAtLogin.unregister() }
    case .approveLaunchAtLogin:
      LaunchAtLogin.openSystemSettings()
      log.write("companion: opened Login Items in System Settings")
    case .openURL(let url):
      openInDefaultApp(url)
    case .setUp:
      openSetup()
    case .reportProblem:
      openReportAProblem()
    case .checkForUpdatesNow:
      performUpdateCheck(manual: true)
    case .copyUpgradeCommand(let command):
      copyToPasteboard(command)
    case .clearDecisionHistory:
      attempt("cleared the decision history", failure: "failed to clear the decision history") {
        try DecisionHistory(paths: paths).clear()
      }
    case .answerPending(let ticketID, let answer):
      answerPending(ticketID: ticketID, answer: answer)
    case .quit:
      quitFromMenu()
    }
  }

  private func answerPending(ticketID: String, answer: MenuAnswer) {
    do {
      guard try queue.sendMenuAnswer(answer, toTicketID: ticketID) else {
        log.write("companion: request \(ticketID) was already gone")
        return
      }
      log.write("companion: answered request \(ticketID) from the menu: \(answer.rawValue)")
    } catch {
      log.write("companion: failed to answer request \(ticketID) from the menu: \(error)")
    }
  }

  private func quitFromMenu() {
    let behavior = loadConfigFile().quitBehavior ?? Settings.defaultQuitBehavior
    var decision = QuitQuestion.decision(for: behavior, pause: pauseSwitch.state)
    if decision == .ask {
      decision = QuitPrompt.ask()
    }
    guard case .quit(let outcome) = decision else { return }
    pendingQuit = outcome
    NSApplication.shared.terminate(nil)
    pendingQuit = nil
  }

  private func apply(_ outcome: QuitOutcome) {
    if outcome.keepsExistingPause {
      log.write("companion: quit without asking, panels were already paused")
    }
    if let remembered = outcome.remembers {
      attempt(
        "saved quitBehavior \"\(remembered.rawValue)\"", failure: "failed to save quitBehavior"
      ) { try rememberQuitBehavior(remembered) }
    }
    guard outcome.pausesPanels else { return }
    do {
      if try stateSwitches.pauseUntilAppOpens() {
        log.write("companion: paused until Countersign opens")
      } else {
        log.write("companion: already paused, the pause stays after Countersign opens")
      }
    } catch {
      log.write("companion: failed to pause: \(error)")
    }
  }

  private func rememberQuitBehavior(_ behavior: QuitBehavior) throws {
    let configFile = paths.configFile
    let original = try ConfigFileStore.read(configFile)
    let updated = try ConfigEdit.applying([.quitBehavior(behavior)], to: original)
    guard updated != original else { return }
    try FileManager.default.createDirectory(
      at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ConfigFileStore.write(updated, to: configFile, date: Date(), backingUp: false)
  }

  private func resumePauseSetAtQuit() {
    do {
      guard try pauseSwitch.resumeIfPausedUntilAppOpens() else { return }
      log.write("companion: resumed the pause set at quit")
    } catch {
      log.write("companion: failed to resume the pause set at quit: \(error)")
    }
  }

  private func attempt(_ done: String, failure: String, _ body: () throws -> Void) {
    do {
      try body()
      log.write("companion: \(done)")
    } catch {
      log.write("companion: \(failure): \(error)")
    }
  }

  private func changeLaunchAtLogin(_ done: String, _ change: () throws -> Void) {
    do {
      try change()
      log.write("companion: \(done)")
    } catch {
      isLaunchAtLoginUnavailable = true
      log.write("companion: launch at login unavailable: \(error)")
    }
  }

  private func opensSettingsAfterUpgrade() -> Bool {
    let current = CountersignVersion.current
    let isUpgrade = UpgradeNudge.isUpgrade(
      lastSeenVersion: UpgradeNudge.readLastSeenVersion(file: paths.lastSeenVersionFile),
      tourShown: FileManager.default.fileExists(atPath: paths.tourShownFile.path),
      currentVersion: current)
    do {
      try UpgradeNudge.recordVersion(current, file: paths.lastSeenVersionFile)
    } catch {
      log.write("companion: could not record the version: \(error)")
    }
    guard isUpgrade else { return false }
    guard UpgradeNudge.needsAgentUpdate(agentWiringStatuses()) else {
      log.write("companion: first run of \(current); agents are up to date")
      return false
    }
    log.write(
      "companion: first run of \(current); an agent needs an update, opening Settings ▸ Agents")
    openSettings(pane: .agents)
    return true
  }

  private func agentWiringStatuses() -> [HostWiringStatus] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let environment = ProcessInfo.processInfo.environment
    guard let resolved = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
      return []
    }
    let stablePath = StableExecutablePath.stable(
      forResolved: resolved, home: home, isExecutable: FileManager.default.isExecutableFile(atPath:)
    )
    let (configFile, _) = ConfigFileLoader.load(
      paths: paths, soundNames: SystemSounds.installedNames)
    let settings = Settings.resolve(file: configFile, host: .claude)
    return ApprovalCore.Host.allCases.map { host in
      let location = HookConfigLocation.location(for: host, environment: environment, home: home)
      return HostWiring.status(
        host: host, directoryExists: DoctorCommand.isInstalled(location),
        file: ConfigFileStore.fileState(location.file), stablePath: stablePath,
        addsWaitingEntry: settings.waitingNotices,
        addsContextEntry: settings.contextCheckpoints.enabled)
    }
  }

  private func openSettings(forceTour: Bool = false, pane: SettingsPane? = nil) {
    if let settingsWindow, !settingsWindow.isClosed {
      settingsWindow.show(forceTour: forceTour, pane: pane)
      return
    }
    SettingsMenu.install()
    let controller = SettingsWindowController(
      model: SettingsModel(environment: .current()),
      onClose: { [weak self] in
        DispatchQueue.main.async { self?.settingsWindow = nil }
      })
    settingsWindow = controller
    controller.show(forceTour: forceTour, pane: pane)
    log.write("companion: opened settings")
  }

  private func openSetup() {
    if let setupWindow {
      setupWindow.show()
      return
    }
    let controller = SetupWindowController(
      model: SetupModel(settings: SettingsModel(environment: .current())),
      onOpenSettings: { [weak self] in
        self?.dropSetupWindow()
        self?.openSettings()
      },
      onClose: { [weak self] in
        self?.dropSetupWindow()
        if self?.settingsWindow?.isClosed ?? true {
          NSApplication.shared.setActivationPolicy(.accessory)
        }
      })
    setupWindow = controller
    controller.show()
    log.write("companion: opened setup")
  }

  private func dropSetupWindow() {
    DispatchQueue.main.async { [weak self] in self?.setupWindow = nil }
  }

  private func openReportAProblem() {
    guard let url = ReportProblem.url() else {
      log.write("companion: could not build the bug report URL")
      return
    }
    openInDefaultApp(url)
  }

  private func openInDefaultApp(_ url: URL) {
    guard !NSWorkspace.shared.open(url) else { return }
    log.write("companion: could not open \(url.absoluteString)")
  }

  private func copyToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      log.write("companion: failed to copy upgrade command")
      return
    }
    log.write("companion: copied upgrade command")
  }
}
