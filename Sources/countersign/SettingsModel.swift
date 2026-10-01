import AppKit
import ApprovalCore
import Foundation
import Observation

struct SettingsEnvironment {
  let paths: AppPaths
  let home: URL
  let locations: [HookConfigLocation]
  let resolvedExecutable: String?
  let runsFromAppBundle: Bool
  let cliIsExecutable: Bool
  let installRoot: URL
  let probesInstallVersions: Bool

  static let snapshotInstallRoot = "root"

  static func current() -> SettingsEnvironment {
    build(
      home: FileManager.default.homeDirectoryForCurrentUser,
      environment: ProcessInfo.processInfo.environment, installRoot: InstallCopiesCheck.systemRoot,
      probesInstallVersions: true)
  }

  static func current(home: URL) -> SettingsEnvironment {
    build(
      home: home, environment: [:],
      installRoot: home.appendingPathComponent(snapshotInstallRoot, isDirectory: true),
      probesInstallVersions: false)
  }

  private static func build(
    home: URL, environment: [String: String], installRoot: URL, probesInstallVersions: Bool
  ) -> SettingsEnvironment {
    SettingsEnvironment(
      paths: AppPaths(
        home: home, xdgConfigHome: environment["XDG_CONFIG_HOME"],
        claudeConfigDir: environment["CLAUDE_CONFIG_DIR"]),
      home: home,
      locations: ApprovalCore.Host.allCases.map {
        HookConfigLocation.location(for: $0, environment: environment, home: home)
      },
      resolvedExecutable: Bundle.main.executableURL?.resolvingSymlinksInPath().path,
      runsFromAppBundle: Bundle.main.bundleIdentifier == AppLaunchMode.bundleIdentifier,
      cliIsExecutable: FileManager.default.isExecutableFile(
        atPath: StableExecutablePath.cliPath(home: home)),
      installRoot: installRoot,
      probesInstallVersions: probesInstallVersions)
  }
}

struct HostRow: Identifiable {
  let location: HookConfigLocation
  var status: HostWiringStatus
  var preview: SetupPreview?
  var showsChanges = false
  var error: String?
  var followUp: AgentFollowUp?

  var id: ApprovalCore.Host { location.host }

  var action: HostWiringAction? {
    HostWiring.action(for: status)
  }

  func shownPath(home: URL) -> String {
    let urls = status == .notInstalled ? location.hostDirectories : [location.file]
    return urls.map { HomePath.abbreviating($0.path, relativeTo: home) }.joined(separator: ", ")
  }

  var problem: String? {
    error ?? preview?.failures.first
  }

  var isWiredOrStale: Bool {
    switch status {
    case .wired, .needsUpdate: return true
    case .notInstalled, .notWired, .unusable: return false
    }
  }

  var canApply: Bool {
    action != nil && preview?.failures.isEmpty != false
  }
}

enum SettingsCopyTarget: Equatable {
  case path
  case prompt
  case upgradeCommand
  case copyStep(Int)
  case agentPrompt
  case versionCommand
}

enum SettingsUpdateCheckPhase: Equatable {
  case idle
  case checking
  case upToDate
  case newerAvailable(UpdateAvailability)
  case failed
}

enum ConfigEditorOrigin: Equatable {
  case advanced
  case host(ApprovalCore.Host)
}

struct EditorOpenFailure {
  let origin: ConfigEditorOrigin
  let message: String
}

enum ContextHookChangeOrigin: Equatable {
  case toggle
  case hookStatus
}

struct ContextHookChange {
  let origin: ContextHookChangeOrigin
  let enable: Bool
  let preview: SetupPreview

  var canApply: Bool {
    preview.failures.isEmpty
  }

  var confirmTitle: String {
    guard origin == .toggle else { return "Update" }
    return enable ? "Turn On" : "Turn Off"
  }
}

struct WaitingHookChange {
  let enable: Bool
  let preview: SetupPreview
  let asksCodexTrust: Bool

  var canApply: Bool {
    preview.failures.isEmpty
  }

  var confirmTitle: String {
    enable ? "Turn On" : "Turn Off"
  }
}

struct ContextHookFailure {
  let origin: ContextHookChangeOrigin
  let message: String
}

@MainActor
@Observable
final class SettingsModel {
  static let copiedFeedback: Duration = .milliseconds(1500)
  static let customAccentPause: Duration = .milliseconds(400)

  let environment: SettingsEnvironment
  let stablePath: String?

  private(set) var hostRows: [HostRow] = []
  private(set) var appLinkOffer: AppBundleLinkOffer?
  private(set) var appLinkMessage: String?
  private(set) var appLinkFailed = false
  private(set) var duplicateInstall: DuplicateInstall?
  private(set) var selectedCopyIndex: Int?
  private(set) var installVersionMismatch: InstallVersionMismatch?
  private(set) var showsCopies = false

  private(set) var status: CountersignStatus
  private(set) var statusError: String?
  private(set) var selectedPane = SettingsPane.standard
  var rememberPane: ((SettingsPane) -> Void)?

  private(set) var preferences = PreferenceValues()
  private(set) var configFileContents = ConfigFile()
  private(set) var snoozeText = PreferenceRules.snoozeText(Settings.defaultSnoozePresets)
  private(set) var snoozeError: String?
  private(set) var newHandoffApp = ""
  private(set) var handoffError: String?
  private(set) var newQuietDays: Set<QuietWeekday> = []
  private(set) var newQuietFrom = ""
  private(set) var newQuietTo = ""
  private(set) var quietHoursError: String?
  private(set) var writeErrors: [PreferenceName: String] = [:]
  private(set) var durationTexts: [PreferenceName: String] = [:]
  private(set) var durationErrors: [PreferenceName: String] = [:]
  private(set) var visit = SettingsVisit()
  private(set) var launchAtLogin = LaunchAtLoginState.unavailable
  private(set) var launchAtLoginError: String?
  private(set) var ownValueNotes: [ApprovalCore.Host: String] = [:]
  private(set) var configProblem: String?
  private(set) var editorOpenFailure: EditorOpenFailure?
  private(set) var testPanelError: String?
  private(set) var contextChange: ContextHookChange?
  private(set) var contextHookFailure: ContextHookFailure?
  private(set) var contextHookStatus = ContextHookStatus.notWired
  private(set) var waitingChange: WaitingHookChange?
  private(set) var waitingHookFailure: String?
  private(set) var delaysPerAgent = false
  private(set) var delayAgent = ApprovalCore.Host.codex
  private(set) var sameDelaysChange: [ApprovalCore.Host]?
  private(set) var contextTexts: [PreferenceName: String] = [:]
  private(set) var contextErrors: [PreferenceName: String] = [:]
  private(set) var newContextModelPrefix = ""
  private(set) var newContextModelLadder = ""
  private(set) var copied: SettingsCopyTarget?
  private(set) var customAccentColor: HexColor?
  private(set) var updateCheckPhase = SettingsUpdateCheckPhase.idle
  var requestClose: (() -> Void)?
  var requestTour: (() -> Void)?
  var applyAppearance: ((AppearanceChoice) -> Void)?

  @ObservationIgnored private var copiedTask: Task<Void, Never>?
  @ObservationIgnored private var customAccentTask: Task<Void, Never>?
  @ObservationIgnored private var configWritten = false
  @ObservationIgnored private var knownConfigBytes: [UInt8]?
  @ObservationIgnored private var isEditingSnoozeMinutes = false
  private let now: () -> Date
  private let savesLearnedCodexTrust: Bool

  init(
    environment: SettingsEnvironment, now: @escaping () -> Date = { Date() },
    status: CountersignStatus? = nil, savesLearnedCodexTrust: Bool = true
  ) {
    self.environment = environment
    self.now = now
    self.savesLearnedCodexTrust = savesLearnedCodexTrust
    self.status = status ?? Self.readStatus(environment.paths)
    stablePath = environment.resolvedExecutable.map {
      StableExecutablePath.stable(
        forResolved: $0, home: environment.home, isExecutable: { _ in environment.cliIsExecutable }
      )
    }
    refreshHosts()
    loadPreferences()
  }

  var configFile: URL {
    environment.paths.configFile
  }

  var configPath: String {
    configFile.path
  }

  var prompt: String {
    SettingsPrompt.text(configPath: configPath)
  }

  var launchAtLoginAvailable: Bool {
    environment.runsFromAppBundle
  }

  var armDelay: Double { preferences.armDelay }
  var chainedArmDelay: Double { preferences.chainedArmDelay }
  var idleSeconds: Double { preferences.idleSeconds }
  var graceSeconds: Double { preferences.graceSeconds }
  var handoffApps: [String] { preferences.handoffApps }
  var quietHours: [QuietWindow] { preferences.quietHours }
  var checkForUpdates: Bool { preferences.checkForUpdates }
  var quitBehavior: QuitBehavior { preferences.quitBehavior }
  var modeAfterPlan: PlanApprovalMode { preferences.modeAfterPlan }
  var panelSound: String { preferences.panelSound }
  var waitingNotices: Bool { preferences.waitingNotices }
  var waitingNoticeDelay: TimeInterval { preferences.waitingNoticeDelay }
  var questionNotes: Bool { preferences.questionNotes }
  var appearance: AppearanceChoice { preferences.appearance }
  var accentColor: HexColor { customAccentColor ?? preferences.accentColor }
  var editorApp: String? { preferences.editorApp }

  var contextCheckpoints: ContextCheckpointSettings { preferences.contextCheckpoints }
  var contextCheckpointsEnabled: Bool { contextCheckpoints.enabled }

  var claudeLocation: HookConfigLocation? {
    environment.locations.first { $0.host == .claude }
  }

  var claudeIsInstalled: Bool {
    claudeLocation.map { DoctorCommand.isInstalled($0) } ?? false
  }

  var contextToggleProblem: String? {
    contextHookProblem(for: .toggle) ?? writeErrors[.contextCheckpointsEnabled]
  }

  var contextModelProblem: String? {
    contextErrors[.contextModelThresholds] ?? writeErrors[.contextModelThresholds]
  }

  var contextModelThresholds: [(prefix: String, ladder: [Int])] {
    contextCheckpoints.modelThresholds.keys.sorted().map {
      ($0, contextCheckpoints.modelThresholds[$0] ?? [])
    }
  }

  func contextHookProblem(for origin: ContextHookChangeOrigin) -> String? {
    guard let contextHookFailure, contextHookFailure.origin == origin else { return nil }
    return contextHookFailure.message
  }

  func contextChange(for origin: ContextHookChangeOrigin) -> ContextHookChange? {
    guard let contextChange, contextChange.origin == origin else { return nil }
    return contextChange
  }

  func contextProblem(_ name: PreferenceName) -> String? {
    contextErrors[name] ?? writeErrors[name]
  }

  var snoozeProblem: String? {
    snoozeError ?? writeErrors[.snoozeMinutes]
  }

  var quietHoursProblem: String? {
    quietHoursError ?? writeErrors[.quietHours]
  }

  var handoffProblem: String? {
    handoffError ?? writeErrors[.handoffApps]
  }

  func select(_ pane: SettingsPane) {
    guard pane != selectedPane else { return }
    selectedPane = pane
    visit.begin()
    rememberPane?(pane)
  }

  func beginVisit() {
    visit.begin()
  }

  func isResettable(_ name: PreferenceName) -> Bool {
    isChanged(name) && visit.contains(name)
  }

  func refreshStatus() {
    let current = Self.readStatus(environment.paths)
    guard current != status else { return }
    status = current
  }

  var headerControls: SettingsHeaderControls {
    SettingsHeaderControls(status: status)
  }

  var snoozeChoices: [TimeInterval] {
    CompanionMenu.snoozePresets(for: configFileContents)
  }

  func togglePause() {
    let controls = headerControls
    let paths = environment.paths
    changeStatus {
      if controls.isPaused {
        try PauseSwitch(file: paths.pauseFile).resume()
      } else {
        try stateSwitches(paths).pause()
      }
    }
  }

  func snooze(seconds: TimeInterval) {
    let paths = environment.paths
    let until = now().addingTimeInterval(seconds)
    changeStatus { try stateSwitches(paths).snooze(until: until) }
  }

  func endQuietTime() {
    let paths = environment.paths
    let endedAt = now()
    changeStatus { try QuietState(paths: paths).endNow(now: endedAt) }
  }

  private func stateSwitches(_ paths: AppPaths) -> StateSwitches {
    StateSwitches(
      pauseSwitch: PauseSwitch(file: paths.pauseFile),
      quietTime: QuietTime(file: paths.quietFile))
  }

  private func changeStatus(_ change: () throws -> Void) {
    do {
      try change()
      statusError = nil
    } catch {
      statusError = SetupRun.describe(error)
    }
    refreshStatus()
  }

  func refreshFromDisk() {
    refreshStatus()
    refreshHosts()
    if launchAtLoginAvailable {
      launchAtLogin = LaunchAtLogin.state
    }
    let current: [UInt8]?
    do {
      current = try ConfigFileStore.read(configFile)
    } catch {
      return
    }
    guard current != knownConfigBytes else { return }
    loadPreferences()
  }

  func refreshHosts() {
    let shown = Dictionary(uniqueKeysWithValues: hostRows.map { ($0.id, $0) })
    hostRows = environment.locations.map { location in
      var row = shown[location.host] ?? HostRow(location: location, status: .notInstalled)
      row.status = status(for: location)
      row.preview = row.action.map { preview(of: location, action: $0) }
      if row.preview?.hasChanges != true {
        row.showsChanges = false
      }
      row.followUp = AgentFollowUps.current(
        host: location.host, wiringStatus: row.status,
        codexTrust: location.host == .codex ? codexHookTrustState(at: location) : .unknown,
        codexHasWaitingEntry: AgentFollowUps.codexHasWaitingEntry(
          in: ConfigFileStore.fileState(location.file)))
      return row
    }
    appLinkOffer = environment.resolvedExecutable.flatMap {
      AppBundleLink.offer(
        resolvedExecutable: $0, home: environment.home, exists: Self.somethingExists)
    }
    let detected = InstallCopiesCheck.duplicates(
      hookExecutables: InstallCopiesCheck.hookExecutables(in: environment.locations),
      runningExecutable: environment.resolvedExecutable, home: environment.home,
      root: environment.installRoot, probesVersions: environment.probesInstallVersions)
    if detected?.entries != duplicateInstall?.entries {
      selectedCopyIndex = detected?.suggestedIndex
    }
    duplicateInstall = detected
    if duplicateInstall == nil {
      showsCopies = false
    }
    installVersionMismatch = InstallCopiesCheck.versionMismatch(
      home: environment.home, root: environment.installRoot,
      probesVersions: environment.probesInstallVersions)
    contextHookStatus = currentContextHookStatus()
  }

  private static let unresolvedExecutable = "the countersign executable could not be resolved"

  private func currentContextHookStatus() -> ContextHookStatus {
    guard let location = claudeLocation else { return .notWired }
    guard let stablePath else { return .unusable(Self.unresolvedExecutable) }
    return ContextHookRun.status(file: location.file, executablePath: stablePath)
  }

  func toggleCopies() {
    showsCopies.toggle()
  }

  func selectCopy(_ index: Int) {
    selectedCopyIndex = index
  }

  var selectedCopySteps: [DuplicateInstallStep] {
    guard let duplicateInstall, let selectedCopyIndex else { return [] }
    return duplicateInstall.steps(keeping: selectedCopyIndex)
  }

  func toggleChanges(_ host: ApprovalCore.Host) {
    guard let index = hostRows.firstIndex(where: { $0.id == host }) else { return }
    hostRows[index].showsChanges.toggle()
  }

  func apply(_ host: ApprovalCore.Host) {
    guard let index = hostRows.firstIndex(where: { $0.id == host }),
      let action = hostRows[index].action
    else { return }
    var run = SetupRun(
      executablePath: stablePath ?? "", uninstall: action.uninstalls,
      addsWaitingEntry: waitingNotices,
      codexHookTrustFile: environment.paths.codexHookTrustFile,
      codexWaitingHookTrustFile: environment.paths.codexWaitingHookTrustFile, now: now,
      output: { _ in }, confirm: { _ in true })
    _ = run.apply(hostRows[index].location)
    hostRows[index].error = run.failures.first
    hostRows[index].showsChanges = false
    refreshHosts()
  }

  func markCodexHookTrustAsDone() {
    guard let index = hostRows.firstIndex(where: { $0.id == .codex }) else { return }
    do {
      try CodexHookTrust.markAsDone(
        hostRows[index].location, recordFile: environment.paths.codexHookTrustFile)
      hostRows[index].error = nil
    } catch {
      hostRows[index].error = SetupRun.describe(error)
    }
    refreshHosts()
  }

  func linkApp() {
    guard let offer = appLinkOffer else { return }
    do {
      try FileManager.default.createDirectory(
        at: offer.link.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(
        atPath: offer.link.path, withDestinationPath: offer.target)
      appLinkMessage =
        "Linked \(HomePath.abbreviating(offer.link.path, relativeTo: environment.home)) to \(offer.target)"
      appLinkFailed = false
    } catch {
      appLinkMessage = SetupRun.describe(error)
      appLinkFailed = true
    }
    refreshHosts()
  }

  func loadPreferences() {
    let bytes: [UInt8]?
    do {
      bytes = try ConfigFileStore.read(configFile)
    } catch {
      configProblem = SetupRun.describe(error)
      knownConfigBytes = nil
      return
    }
    knownConfigBytes = bytes
    configProblem = ConfigEdit.problem(in: bytes)
    let parsedFile =
      bytes.map {
        ConfigFileParser.parse(Data($0), soundNames: SystemSounds.installedNames).file
      } ?? ConfigFile()
    configFileContents = parsedFile
    preferences = PreferenceValues(file: parsedFile)
    if !delaysPerAgent, let first = PreferenceOverrides.agentsWithOwnDelays(in: parsedFile).first {
      delaysPerAgent = true
      delayAgent = first
    }
    CountersignPalette.use(accentColor)
    applyAppearance?(appearance)
    if !isEditingSnoozeMinutes, snoozeError == nil {
      showSnoozeMinutes()
    }
    ownValueNotes = Dictionary(
      uniqueKeysWithValues: ApprovalCore.Host.allCases.compactMap { host in
        PreferenceOverrides.note(for: host, in: parsedFile).map { (host, $0) }
      })
    if launchAtLoginAvailable {
      launchAtLogin = LaunchAtLogin.state
    }
    if selectedPane == .context, !contextCheckpointsEnabled {
      select(.panels)
    }
  }

  func setArmDelay(_ value: Double) {
    writeDelay(.armDelay(PreferenceRules.armDelay(value)))
  }

  func setChainedArmDelay(_ value: Double) {
    writeDelay(.chainedArmDelay(PreferenceRules.chainedArmDelay(value)))
  }

  func setIdleSeconds(_ value: Double) {
    writeDelay(.idleSeconds(PreferenceRules.idleSeconds(value)))
  }

  func setGraceSeconds(_ value: Double) {
    writeDelay(.graceSeconds(PreferenceRules.graceSeconds(value)))
  }

  func setApprovalCardDelay(_ value: TimeInterval) {
    writeDelay(.approvalCardDelay(value))
  }

  private func writeDelay(_ edit: PreferenceEdit) {
    dropDurationText(edit.key)
    write(delaysPerAgent ? .forAgent(delayAgent, edit) : edit)
  }

  private func dropDurationText(_ name: PreferenceName) {
    durationTexts[name] = nil
    durationErrors[name] = nil
  }

  private func dropAgentDelayTexts() {
    for name in PreferenceName.agentDelays {
      dropDurationText(name)
      writeErrors[name] = nil
    }
  }

  func setDelayAgent(_ host: ApprovalCore.Host) {
    guard host != delayAgent else { return }
    dropAgentDelayTexts()
    delayAgent = host
  }

  func requestSameDelays(_ enable: Bool) {
    guard enable == delaysPerAgent else { return }
    guard enable else {
      dropAgentDelayTexts()
      delaysPerAgent = true
      return
    }
    let agents = PreferenceOverrides.agentsWithOwnDelays(in: configFileContents)
    guard agents.isEmpty else {
      sameDelaysChange = agents
      return
    }
    dropAgentDelayTexts()
    delaysPerAgent = false
  }

  func cancelSameDelays() {
    sameDelaysChange = nil
  }

  func confirmSameDelays() {
    guard sameDelaysChange != nil else { return }
    sameDelaysChange = nil
    dropAgentDelayTexts()
    guard write(PreferenceEdit.removingAgentDelays(in: configFileContents)) else { return }
    delaysPerAgent = false
  }

  var approvalCardAgents: [ApprovalCore.Host] { preferences.approvalCardAgents }

  func setApprovalCard(_ enabled: Bool, for host: ApprovalCore.Host) {
    write(.forAgent(host, .approvalCard(enabled)))
  }

  var showsApprovalCardDelay: Bool {
    delaysPerAgent ? approvalCardAgents.contains(delayAgent) : !approvalCardAgents.isEmpty
  }

  func shownDelay(_ name: PreferenceName) -> TimeInterval {
    guard delaysPerAgent else { return sharedDelay(name) }
    return ownDelay(name) ?? sharedDelay(name)
  }

  private func sharedDelay(_ name: PreferenceName) -> TimeInterval {
    switch name {
    case .idleSeconds: return preferences.idleSeconds
    case .graceSeconds: return preferences.graceSeconds
    case .armDelay: return preferences.armDelay
    case .chainedArmDelay: return preferences.chainedArmDelay
    case .waitingNoticeMinutes: return preferences.waitingNoticeDelay
    case .approvalCardDelay: return preferences.approvalCardDelay
    default: return 0
    }
  }

  private func ownDelay(_ name: PreferenceName) -> TimeInterval? {
    guard let overrides = configFileContents.overrides(for: delayAgent) else { return nil }
    switch name {
    case .idleSeconds: return overrides.idleSeconds
    case .graceSeconds: return overrides.graceSeconds
    case .armDelay: return overrides.armDelay
    case .chainedArmDelay: return overrides.chainedArmDelay
    case .waitingNoticeMinutes: return overrides.waitingNoticeDelay
    case .approvalCardDelay: return overrides.approvalCardDelay
    default: return nil
    }
  }

  func durationText(_ name: PreferenceName) -> String {
    if let pending = durationTexts[name] { return pending }
    guard delaysPerAgent else { return DurationText.compact(sharedDelay(name)) }
    return ownDelay(name).map { DurationText.compact($0) } ?? ""
  }

  func durationPlaceholder(_ name: PreferenceName) -> String {
    guard delaysPerAgent else { return name.title }
    return DurationText.compact(sharedDelay(name))
  }

  func setDurationText(_ text: String, for name: PreferenceName) {
    guard let spec = name.durationField else { return }
    durationTexts[name] = text
    if delaysPerAgent, text.trimmingCharacters(in: .whitespaces).isEmpty {
      durationErrors[name] = nil
      return
    }
    switch PreferenceRules.duration(from: text, spec: spec) {
    case .success:
      durationErrors[name] = nil
    case .failure(let error):
      durationErrors[name] = error.description
    }
  }

  func commitDuration(_ name: PreferenceName) {
    guard let spec = name.durationField, let text = durationTexts[name] else { return }
    if delaysPerAgent, text.trimmingCharacters(in: .whitespaces).isEmpty {
      dropDurationText(name)
      write(.forAgent(delayAgent, .reset(name)))
      return
    }
    guard case .success(let seconds) = PreferenceRules.duration(from: text, spec: spec) else {
      return
    }
    switch name {
    case .idleSeconds: setIdleSeconds(seconds)
    case .graceSeconds: setGraceSeconds(seconds)
    case .armDelay: setArmDelay(seconds)
    case .chainedArmDelay: setChainedArmDelay(seconds)
    case .waitingNoticeMinutes: setWaitingNoticeDelay(seconds)
    case .approvalCardDelay: setApprovalCardDelay(seconds)
    default: return
    }
    dropDurationText(name)
  }

  func durationProblem(_ name: PreferenceName) -> String? {
    durationErrors[name] ?? writeErrors[name]
  }

  func setSnoozeText(_ text: String) {
    guard text != snoozeText else { return }
    snoozeText = text
    switch PreferenceRules.snoozePresets(from: text) {
    case .success:
      snoozeError = nil
    case .failure(let error):
      snoozeError = error.description
    }
  }

  func setEditingSnoozeMinutes(_ editing: Bool) {
    isEditingSnoozeMinutes = editing
    guard !editing else { return }
    commitSnoozeMinutes()
  }

  func commitSnoozeMinutes() {
    guard case .success(let presets) = PreferenceRules.snoozePresets(from: snoozeText) else {
      return
    }
    write(.snoozePresets(presets))
    showSnoozeMinutes()
  }

  func toggleNewQuietDay(_ day: QuietWeekday) {
    if newQuietDays.contains(day) {
      newQuietDays.remove(day)
    } else {
      newQuietDays.insert(day)
    }
    quietHoursError = nil
  }

  func setNewQuietFrom(_ text: String) {
    newQuietFrom = text
    quietHoursError = nil
  }

  func setNewQuietTo(_ text: String) {
    newQuietTo = text
    quietHoursError = nil
  }

  func addQuietWindow() {
    let days = QuietWeekday.allCases.filter { newQuietDays.contains($0) }
    switch PreferenceRules.quietWindow(
      days: days, from: newQuietFrom, to: newQuietTo, joining: quietHours)
    {
    case .success(let window):
      quietHoursError = nil
      if write(.quietHours(quietHours + [window])) {
        clearNewQuietWindow()
      }
    case .failure(let error):
      quietHoursError = error.description
    }
  }

  func removeQuietWindow(_ window: QuietWindow) {
    write(.quietHours(quietHours.filter { $0 != window }))
  }

  private func clearNewQuietWindow() {
    newQuietDays = []
    newQuietFrom = ""
    newQuietTo = ""
    quietHoursError = nil
  }

  func setNewHandoffApp(_ text: String) {
    newHandoffApp = text
    handoffError = nil
  }

  func addHandoffApp() {
    switch PreferenceRules.handoffApp(newHandoffApp, joining: handoffApps) {
    case .success(let bundleID):
      handoffError = nil
      if write(.addHandoffApp(bundleID)) {
        newHandoffApp = ""
      }
    case .failure(let error):
      handoffError = error.description
    }
  }

  func commitNewHandoffApp() {
    guard !newHandoffApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    addHandoffApp()
  }

  func removeHandoffApp(_ bundleID: String) {
    write(.removeHandoffApp(bundleID))
  }

  func setCheckForUpdates(_ enabled: Bool) {
    write(.checkForUpdates(enabled))
  }

  func setQuitBehavior(_ behavior: QuitBehavior) {
    write(.quitBehavior(behavior))
  }

  func setModeAfterPlan(_ mode: PlanApprovalMode) {
    write(.modeAfterPlan(mode))
  }

  func setPanelSound(_ name: String) {
    write(.panelSound(name))
  }

  func setWaitingNoticeDelay(_ seconds: TimeInterval) {
    writeDelay(.waitingNoticeDelay(seconds))
  }

  var homeDirectory: URL {
    environment.home
  }

  var waitingToggleProblem: String? {
    waitingHookFailure ?? writeErrors[.waitingNotices]
  }

  var waitingLocations: [HookConfigLocation] {
    hostRows
      .filter { WaitingHookSetup.supportedHosts.contains($0.id) && $0.isWiredOrStale }
      .map(\.location)
  }

  func requestWaitingNotices(_ enable: Bool) {
    guard enable != waitingNotices else { return }
    waitingHookFailure = nil
    let locations = waitingLocations
    if enable, !locations.isEmpty, stablePath == nil {
      waitingChange = nil
      waitingHookFailure = Self.unresolvedExecutable
      return
    }
    let preview = WaitingHookRun.preview(
      locations: locations, executablePath: stablePath ?? "", enable: enable)
    let codexFile = locations.first { $0.host == .codex }?.file
    waitingChange = WaitingHookChange(
      enable: enable, preview: preview,
      asksCodexTrust: enable && codexFile.map { preview.changedFiles.contains($0) } == true)
  }

  func cancelWaitingChange() {
    waitingChange = nil
  }

  func confirmWaitingChange() {
    guard let change = waitingChange, change.canApply else { return }
    waitingChange = nil
    let failures = WaitingHookRun.apply(
      locations: waitingLocations, executablePath: stablePath ?? "", enable: change.enable,
      now: now(), codexWaitingTrustFile: environment.paths.codexWaitingHookTrustFile)
    guard failures.isEmpty else {
      waitingHookFailure = failures.joined(separator: "\n")
      refreshHosts()
      return
    }
    waitingHookFailure = nil
    write(.waitingNotices(change.enable))
    refreshHosts()
  }

  func setQuestionNotes(_ enabled: Bool) {
    write(.questionNotes(enabled))
  }

  func setAppearance(_ appearance: AppearanceChoice) {
    write(.appearance(appearance))
  }

  func setAccentColor(_ color: HexColor) {
    discardCustomAccentColor()
    write(.accentColor(color))
  }

  func pickCustomAccentColor(_ color: HexColor) {
    guard color != accentColor else { return }
    customAccentColor = color
    CountersignPalette.use(color)
    customAccentTask?.cancel()
    customAccentTask = Task { [weak self] in
      try? await Task.sleep(for: Self.customAccentPause)
      guard !Task.isCancelled else { return }
      self?.commitCustomAccentColor()
    }
  }

  func commitCustomAccentColor() {
    guard let color = customAccentColor else { return }
    discardCustomAccentColor()
    write(.accentColor(color))
  }

  private func discardCustomAccentColor() {
    customAccentTask?.cancel()
    customAccentTask = nil
    guard customAccentColor != nil else { return }
    customAccentColor = nil
    CountersignPalette.use(accentColor)
  }

  func setEditorApp(_ bundleID: String) {
    write(.editorApp(bundleID))
  }

  func commitEditing() {
    commitSnoozeMinutes()
    commitNewHandoffApp()
    commitCustomAccentColor()
    for name in Self.editableContextTexts {
      commitContextText(name)
    }
    commitNewContextModel()
  }

  static let editableContextTexts: [PreferenceName] = [
    .contextStandardThresholds, .contextMillionThresholds, .contextHandoffFile,
  ]

  static let contextNoteNames: [PreferenceName] = [
    .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteCompact,
    .contextNoteHandoff,
  ]

  var contextHookFileText: String? {
    claudeLocation.map { HomePath.abbreviating($0.file.path, relativeTo: environment.home) }
  }

  func saveContextNotes(_ drafts: [PreferenceName: String]) -> Bool {
    var edits: [(name: PreferenceName, edit: PreferenceEdit)] = []
    var allValid = true
    for name in Self.contextNoteNames {
      guard let text = drafts[name], text != contextText(for: name) else { continue }
      switch contextEdit(for: name, text: text) {
      case .success(let edit):
        contextErrors[name] = nil
        edits.append((name, edit))
      case .failure(let error):
        contextErrors[name] = error.description
        allValid = false
      }
    }
    guard allValid else { return false }
    var allWritten = true
    for entry in edits {
      if !write(entry.edit) {
        allWritten = false
      }
    }
    return allWritten
  }

  func clearContextNoteErrors() {
    for name in Self.contextNoteNames {
      contextErrors[name] = nil
      writeErrors[name] = nil
    }
  }

  func requestContextCheckpoints(_ enable: Bool) {
    guard enable != contextCheckpointsEnabled else { return }
    requestContextHookChange(origin: .toggle, enable: enable)
  }

  func requestContextHookUpdate() {
    requestContextHookChange(origin: .hookStatus, enable: true)
  }

  private func requestContextHookChange(origin: ContextHookChangeOrigin, enable: Bool) {
    guard let location = claudeLocation else { return }
    contextHookFailure = nil
    if enable, stablePath == nil {
      contextChange = nil
      contextHookFailure = ContextHookFailure(origin: origin, message: Self.unresolvedExecutable)
      return
    }
    contextChange = ContextHookChange(
      origin: origin, enable: enable,
      preview: ContextHookRun.preview(
        file: location.file, executablePath: stablePath ?? "", enable: enable))
  }

  func cancelContextChange() {
    if let change = contextChange, let line = change.preview.failures.first {
      contextHookFailure = ContextHookFailure(origin: change.origin, message: line)
    }
    contextChange = nil
  }

  func confirmContextChange() {
    guard let change = contextChange, change.canApply, let location = claudeLocation else {
      return
    }
    contextChange = nil
    if let line = ContextHookRun.apply(
      file: location.file, executablePath: stablePath ?? "", enable: change.enable, now: now())
    {
      contextHookFailure = ContextHookFailure(origin: change.origin, message: line)
      refreshHosts()
      return
    }
    contextHookFailure = nil
    if change.origin == .toggle {
      if !change.enable {
        ContextCheckpointStore(directory: environment.paths.contextCheckpointsDirectory)
          .removeAll()
      }
      write(.contextCheckpointsEnabled(change.enable))
    }
    refreshHosts()
  }

  func contextText(for name: PreferenceName) -> String {
    if let pending = contextTexts[name] { return pending }
    let values = contextCheckpoints
    switch name {
    case .contextStandardThresholds:
      return PreferenceRules.contextLadderText(values.standardThresholds)
    case .contextMillionThresholds:
      return PreferenceRules.contextLadderText(values.millionThresholds)
    case .contextHandoffFile: return values.handoffFile
    case .contextNoteSoft: return values.notes.soft
    case .contextNoteStatus: return values.notes.status
    case .contextNoteInsist: return values.notes.insist
    case .contextNoteCompact: return values.notes.compact
    case .contextNoteHandoff: return values.notes.handoff
    default: return ""
    }
  }

  func setContextText(_ text: String, for name: PreferenceName) {
    contextTexts[name] = text
    switch contextEdit(for: name, text: text) {
    case .success: contextErrors[name] = nil
    case .failure(let error): contextErrors[name] = error.description
    }
  }

  func commitContextText(_ name: PreferenceName) {
    guard let text = contextTexts[name] else { return }
    switch contextEdit(for: name, text: text) {
    case .success(let edit):
      contextErrors[name] = nil
      if write(edit) {
        contextTexts[name] = nil
      }
    case .failure(let error):
      contextErrors[name] = error.description
    }
  }

  private func contextEdit(for name: PreferenceName, text: String) -> Result<
    PreferenceEdit, ContextTextError
  > {
    switch name {
    case .contextStandardThresholds:
      return PreferenceRules.contextLadder(fromThousands: text).map {
        PreferenceEdit.contextStandardThresholds($0)
      }
    case .contextMillionThresholds:
      return PreferenceRules.contextLadder(fromThousands: text).map {
        PreferenceEdit.contextMillionThresholds($0)
      }
    case .contextHandoffFile:
      return PreferenceRules.contextHandoffFile(text).map { PreferenceEdit.contextHandoffFile($0) }
    default:
      return PreferenceRules.contextNote(text).map { PreferenceEdit.contextNote(name, $0) }
    }
  }

  func setContextMode(_ mode: ContextCheckpointMode) {
    write(.contextMode(mode))
  }

  func setContextRearmBelow(_ ratio: Double) {
    write(.contextRearmBelow(ratio))
  }

  func setContextMenuBarMeter(_ enabled: Bool) {
    write(.contextMenuBarMeter(enabled))
  }

  func setNewContextModelPrefix(_ text: String) {
    newContextModelPrefix = text
    contextErrors[.contextModelThresholds] = nil
  }

  func setNewContextModelLadder(_ text: String) {
    newContextModelLadder = text
    contextErrors[.contextModelThresholds] = nil
  }

  func addContextModel() {
    switch (
      PreferenceRules.contextModelPrefix(newContextModelPrefix),
      PreferenceRules.contextLadder(fromThousands: newContextModelLadder)
    ) {
    case (.failure(let error), _), (_, .failure(let error)):
      contextErrors[.contextModelThresholds] = error.description
    case (.success(let prefix), .success(let ladder)):
      contextErrors[.contextModelThresholds] = nil
      if write(.setContextModelThresholds(prefix: prefix, ladder: ladder)) {
        newContextModelPrefix = ""
        newContextModelLadder = ""
      }
    }
  }

  func commitNewContextModel() {
    guard !newContextModelPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !newContextModelLadder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    addContextModel()
  }

  func removeContextModel(_ prefix: String) {
    write(.removeContextModelThresholds(prefix: prefix))
  }

  func isChanged(_ name: PreferenceName) -> Bool {
    PreferenceReset.isChanged(name, in: configFileContents)
  }

  func changedNames(in names: [PreferenceName]) -> [PreferenceName] {
    PreferenceReset.changedNames(in: configFileContents, within: names)
  }

  func restoreDefaultsConfirmationLines(for pane: SettingsPane) -> [String] {
    let names = pane.preferenceNames
    return PreferenceReset.confirmationLines(
      changed: changedNames(in: names), group: names, current: preferences,
      file: configFileContents)
  }

  func reset(_ name: PreferenceName) {
    discardPendingText(for: [name])
    write(.reset(name))
  }

  func resetGroup(_ names: [PreferenceName]) {
    let changed = changedNames(in: names)
    guard !changed.isEmpty else { return }
    discardPendingText(for: changed)
    write(changed.map { PreferenceEdit.reset($0) })
  }

  private func discardPendingText(for names: [PreferenceName]) {
    if names.contains(.snoozeMinutes) {
      isEditingSnoozeMinutes = false
      snoozeError = nil
    }
    if names.contains(.handoffApps) {
      newHandoffApp = ""
      handoffError = nil
    }
    if names.contains(.quietHours) {
      clearNewQuietWindow()
    }
    if names.contains(.accentColor) {
      discardCustomAccentColor()
    }
    for name in names {
      durationTexts[name] = nil
      durationErrors[name] = nil
      contextTexts[name] = nil
      contextErrors[name] = nil
    }
    if names.contains(.contextModelThresholds) {
      newContextModelPrefix = ""
      newContextModelLadder = ""
    }
  }

  @discardableResult
  private func write(_ edit: PreferenceEdit) -> Bool {
    write([edit])
  }

  @discardableResult
  private func write(_ edits: [PreferenceEdit]) -> Bool {
    let shown = preferences
    let chosen = edits.reduce(shown) { $0.applying($1) }
    let editsAgentFile = edits.contains {
      if case .forAgent = $0 { return true }
      return false
    }
    guard chosen != shown || editsAgentFile else { return true }
    preferences = chosen
    do {
      let original = try ConfigFileStore.read(configFile)
      let updated = try ConfigEdit.applying(edits, to: original)
      if updated != original {
        try FileManager.default.createDirectory(
          at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigFileStore.write(updated, to: configFile, date: now(), backingUp: !configWritten)
        configWritten = true
      }
    } catch {
      for edit in edits {
        writeErrors[edit.key] = "\(configPath): error: \(SetupRun.describe(error))"
      }
      preferences = shown
      loadPreferences()
      return false
    }
    for edit in edits {
      writeErrors[edit.key] = nil
    }
    recordVisit(of: edits)
    loadPreferences()
    return true
  }

  private func recordVisit(of edits: [PreferenceEdit]) {
    var written: [PreferenceName] = []
    var reset: [PreferenceName] = []
    for edit in edits {
      switch edit {
      case .reset(let name): reset.append(name)
      case .forAgent(_, .approvalCard): written.append(.approvalCard)
      case .forAgent: break
      default: written.append(edit.key)
      }
    }
    visit.record(written)
    visit.forget(reset)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard launchAtLoginAvailable else { return }
    do {
      if enabled {
        try LaunchAtLogin.register()
      } else {
        try LaunchAtLogin.unregister()
      }
      launchAtLoginError = nil
    } catch {
      launchAtLoginError = SetupRun.describe(error)
    }
    launchAtLogin = LaunchAtLogin.state
  }

  func approveLaunchAtLogin() {
    LaunchAtLogin.openSystemSettings()
  }

  func openConfigInEditor(from origin: ConfigEditorOrigin = .advanced) {
    do {
      if try ConfigFileStarter.createIfMissing(paths: environment.paths) {
        loadPreferences()
      }
    } catch {
      editorOpenFailure = EditorOpenFailure(
        origin: origin, message: "\(configPath): error: \(SetupRun.describe(error))")
      return
    }
    guard let bundleID = editorApp else {
      openWithDefaultApp(origin: origin)
      return
    }
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      openWithDefaultApp(origin: origin, missingBundleID: bundleID)
      return
    }
    NSWorkspace.shared.open(
      [configFile], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    editorOpenFailure = nil
  }

  private func openWithDefaultApp(origin: ConfigEditorOrigin, missingBundleID: String? = nil) {
    guard NSWorkspace.shared.open(configFile) else {
      editorOpenFailure = EditorOpenFailure(
        origin: origin, message: "\(configPath) could not be opened")
      return
    }
    editorOpenFailure = missingBundleID.map {
      EditorOpenFailure(
        origin: origin, message: "\($0) is not installed; opened with the default app.")
    }
  }

  func editorOpenProblem(at origin: ConfigEditorOrigin) -> String? {
    guard let editorOpenFailure, editorOpenFailure.origin == origin else { return nil }
    return editorOpenFailure.message
  }

  var isTestPanelRunning: Bool { TestPanelLauncher.shared.isRunning }

  func showTestPanel(_ kind: TestPanelKind) {
    commitEditing()
    do {
      try TestPanelLauncher.shared.launch(kind: kind) { [weak self] refusal in
        self?.testPanelError = "The test panel didn't show: \(refusal)"
      }
      testPanelError = nil
    } catch {
      testPanelError = "The test panel could not start: \(SetupRun.describe(error))"
    }
  }

  func copy(_ target: SettingsCopyTarget) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text(for: target), forType: .string)
    copied = target
    copiedTask?.cancel()
    copiedTask = Task { [weak self] in
      try? await Task.sleep(for: Self.copiedFeedback)
      guard !Task.isCancelled else { return }
      self?.copied = nil
    }
  }

  private func text(for target: SettingsCopyTarget) -> String {
    switch target {
    case .path: return configPath
    case .prompt: return prompt
    case .upgradeCommand:
      guard case .newerAvailable(let availability) = updateCheckPhase else { return "" }
      return availability.upgradeCommand
    case .copyStep(let index):
      let steps = selectedCopySteps
      return steps.indices.contains(index) ? steps[index].command ?? "" : ""
    case .agentPrompt: return duplicateInstall?.agentPrompt ?? ""
    case .versionCommand: return installVersionMismatch?.command ?? ""
    }
  }

  func checkForUpdates() async {
    guard updateCheckPhase != .checking else { return }
    updateCheckPhase = .checking
    let outcome = await UpdateFetcher.fetch(currentVersion: CountersignVersion.current)
    updateCheckPhase = Self.phase(for: outcome)
  }

  private static func phase(for outcome: UpdateCheckOutcome) -> SettingsUpdateCheckPhase {
    switch outcome {
    case .newerAvailable(let version):
      let resolvedExecutablePath =
        Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "(unresolved)"
      return .newerAvailable(
        UpdateAvailability(
          version: version,
          upgradeCommand: UpdateCommand.upgrade(forResolvedExecutablePath: resolvedExecutablePath),
          releaseNotesURL: UpdateCommand.releaseNotesURL(version: version)))
    case .upToDate:
      return .upToDate
    case .unknown:
      return .failed
    }
  }

  private func showSnoozeMinutes() {
    snoozeText = PreferenceRules.snoozeText(preferences.snoozePresets)
    snoozeError = nil
  }

  private func status(for location: HookConfigLocation) -> HostWiringStatus {
    guard let stablePath else {
      return .unusable("the countersign executable could not be resolved")
    }
    return HostWiring.status(
      host: location.host, directoryExists: DoctorCommand.isInstalled(location),
      file: ConfigFileStore.fileState(location.file), stablePath: stablePath,
      addsWaitingEntry: waitingNotices)
  }

  private func preview(of location: HookConfigLocation, action: HostWiringAction)
    -> SetupPreview
  {
    SetupRun.preview(
      location, executablePath: stablePath ?? "", uninstall: action.uninstalls,
      addsWaitingEntry: waitingNotices)
  }

  private func codexHookTrustState(at location: HookConfigLocation) -> CodexHookTrustState {
    CodexHookTrust.check(
      location, recordFile: environment.paths.codexHookTrustFile,
      persistsLearnedHash: savesLearnedCodexTrust)
  }

  private static func readStatus(_ paths: AppPaths) -> CountersignStatus {
    CountersignStatus.current(
      pause: PauseSwitch(file: paths.pauseFile).state,
      quietUntil: QuietState(paths: paths).activeUntil())
  }

  private static func somethingExists(_ path: String) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: path)) != nil
  }
}
