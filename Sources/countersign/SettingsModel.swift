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
  private(set) var snoozeText = PreferenceRules.snoozeText(Settings.defaultSnoozeMinutes)
  private(set) var snoozeError: String?
  private(set) var newHandoffApp = ""
  private(set) var handoffError: String?
  private(set) var writeErrors: [PreferenceName: String] = [:]
  private(set) var launchAtLogin = LaunchAtLoginState.unavailable
  private(set) var launchAtLoginError: String?
  private(set) var ownValueNotes: [ApprovalCore.Host: String] = [:]
  private(set) var configProblem: String?
  private(set) var editorOpenFailure: EditorOpenFailure?
  private(set) var testPanelError: String?
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
  var checkForUpdates: Bool { preferences.checkForUpdates }
  var quitBehavior: QuitBehavior { preferences.quitBehavior }
  var modeAfterPlan: PlanApprovalMode { preferences.modeAfterPlan }
  var questionNotes: Bool { preferences.questionNotes }
  var appearance: AppearanceChoice { preferences.appearance }
  var accentColor: HexColor { customAccentColor ?? preferences.accentColor }
  var editorApp: String? { preferences.editorApp }

  var snoozeProblem: String? {
    snoozeError ?? writeErrors[.snoozeMinutes]
  }

  var handoffProblem: String? {
    handoffError ?? writeErrors[.handoffApps]
  }

  func select(_ pane: SettingsPane) {
    guard pane != selectedPane else { return }
    selectedPane = pane
    rememberPane?(pane)
  }

  func refreshStatus() {
    let current = Self.readStatus(environment.paths)
    guard current != status else { return }
    status = current
  }

  func performStatusAction() {
    let paths = environment.paths
    do {
      switch status.action {
      case .pause:
        try StateSwitches(
          pauseSwitch: PauseSwitch(file: paths.pauseFile),
          quietTime: QuietTime(file: paths.quietFile)
        ).pause()
      case .resume:
        try PauseSwitch(file: paths.pauseFile).resume()
      case .endQuietTime:
        try QuietTime(file: paths.quietFile).clear()
      }
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
        codexTrust: location.host == .codex ? codexHookTrustState(at: location) : .unknown)
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
      codexHookTrustFile: environment.paths.codexHookTrustFile, now: now,
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
    let parsedFile = bytes.map { ConfigFileParser.parse(Data($0)).file } ?? ConfigFile()
    configFileContents = parsedFile
    preferences = PreferenceValues(file: parsedFile)
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
  }

  func setArmDelay(_ value: Double) {
    write(.armDelay(PreferenceRules.armDelay(value)))
  }

  func setChainedArmDelay(_ value: Double) {
    write(.chainedArmDelay(PreferenceRules.chainedArmDelay(value)))
  }

  func setIdleSeconds(_ value: Double) {
    write(.idleSeconds(PreferenceRules.idleSeconds(value)))
  }

  func setGraceSeconds(_ value: Double) {
    write(.graceSeconds(PreferenceRules.graceSeconds(value)))
  }

  func setSnoozeText(_ text: String) {
    guard text != snoozeText else { return }
    snoozeText = text
    switch PreferenceRules.snoozeMinutes(from: text) {
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
    guard case .success(let minutes) = PreferenceRules.snoozeMinutes(from: snoozeText) else {
      return
    }
    write(.snoozeMinutes(minutes))
    showSnoozeMinutes()
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
    if names.contains(.accentColor) {
      discardCustomAccentColor()
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
    guard chosen != shown else { return true }
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
    loadPreferences()
    return true
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
    snoozeText = PreferenceRules.snoozeText(preferences.snoozeMinutes)
    snoozeError = nil
  }

  private func status(for location: HookConfigLocation) -> HostWiringStatus {
    guard let stablePath else {
      return .unusable("the countersign executable could not be resolved")
    }
    return HostWiring.status(
      host: location.host, directoryExists: DoctorCommand.isInstalled(location),
      file: ConfigFileStore.fileState(location.file), stablePath: stablePath)
  }

  private func preview(of location: HookConfigLocation, action: HostWiringAction)
    -> SetupPreview
  {
    SetupRun.preview(location, executablePath: stablePath ?? "", uninstall: action.uninstalls)
  }

  private func codexHookTrustState(at location: HookConfigLocation) -> CodexHookTrustState {
    CodexHookTrust.check(
      location, recordFile: environment.paths.codexHookTrustFile,
      persistsLearnedHash: savesLearnedCodexTrust)
  }

  private static func readStatus(_ paths: AppPaths) -> CountersignStatus {
    CountersignStatus.current(
      pause: PauseSwitch(file: paths.pauseFile).state,
      quietUntil: QuietTime(file: paths.quietFile).activeUntil())
  }

  private static func somethingExists(_ path: String) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: path)) != nil
  }
}
