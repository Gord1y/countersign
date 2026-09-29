import Foundation

extension ContextCheckpointNotes {
  func text(for name: PreferenceName) -> String? {
    name.noteName.flatMap { text(named: $0) }
  }

  mutating func set(_ text: String, named name: PreferenceName) {
    switch name {
    case .contextNoteSoft: soft = text
    case .contextNoteStatus: status = text
    case .contextNoteInsist: insist = text
    case .contextNoteCompact: compact = text
    case .contextNoteHandoff: handoff = text
    default: break
    }
  }
}

public struct PreferenceValues: Sendable, Equatable {
  public var armDelay: Double
  public var chainedArmDelay: Double
  public var idleSeconds: Double
  public var graceSeconds: Double
  public var snoozeMinutes: [Int]
  public var handoffApps: [String]
  public var checkForUpdates: Bool
  public var quitBehavior: QuitBehavior
  public var modeAfterPlan: PlanApprovalMode
  public var questionNotes: Bool
  public var appearance: AppearanceChoice
  public var accentColor: HexColor
  public var editorApp: String?
  public var contextCheckpoints: ContextCheckpointSettings

  public init(
    armDelay: Double = Settings.defaultArmDelay,
    chainedArmDelay: Double = Settings.defaultChainedArmDelay,
    idleSeconds: Double = Settings.defaultIdleSeconds,
    graceSeconds: Double = Settings.defaultGraceSeconds,
    snoozeMinutes: [Int] = Settings.defaultSnoozeMinutes,
    handoffApps: [String] = Settings.defaultHandoffApps,
    checkForUpdates: Bool = Settings.defaultCheckForUpdates,
    quitBehavior: QuitBehavior = Settings.defaultQuitBehavior,
    modeAfterPlan: PlanApprovalMode = Settings.defaultModeAfterPlan,
    questionNotes: Bool = Settings.defaultQuestionNotes,
    appearance: AppearanceChoice = Settings.defaultAppearance,
    accentColor: HexColor = Settings.defaultAccentColor,
    editorApp: String? = nil,
    contextCheckpoints: ContextCheckpointSettings = .default
  ) {
    self.armDelay = armDelay
    self.chainedArmDelay = chainedArmDelay
    self.idleSeconds = idleSeconds
    self.graceSeconds = graceSeconds
    self.snoozeMinutes = snoozeMinutes
    self.handoffApps = handoffApps
    self.checkForUpdates = checkForUpdates
    self.quitBehavior = quitBehavior
    self.modeAfterPlan = modeAfterPlan
    self.questionNotes = questionNotes
    self.appearance = appearance
    self.accentColor = accentColor
    self.editorApp = editorApp
    self.contextCheckpoints = contextCheckpoints
  }

  public init(file: ConfigFile) {
    self.init(
      armDelay: file.armDelay ?? Settings.defaultArmDelay,
      chainedArmDelay: file.chainedArmDelay ?? Settings.defaultChainedArmDelay,
      idleSeconds: file.idleSeconds ?? Settings.defaultIdleSeconds,
      graceSeconds: file.graceSeconds ?? Settings.defaultGraceSeconds,
      snoozeMinutes: file.snoozeMinutes ?? Settings.defaultSnoozeMinutes,
      handoffApps: file.handoffApps ?? Settings.defaultHandoffApps,
      checkForUpdates: file.checkForUpdates ?? Settings.defaultCheckForUpdates,
      quitBehavior: file.quitBehavior ?? Settings.defaultQuitBehavior,
      modeAfterPlan: file.modeAfterPlan ?? Settings.defaultModeAfterPlan,
      questionNotes: file.questionNotes ?? Settings.defaultQuestionNotes,
      appearance: file.appearance ?? Settings.defaultAppearance,
      accentColor: file.accentColor ?? Settings.defaultAccentColor,
      editorApp: file.editorApp,
      contextCheckpoints: ContextCheckpointSettings.resolve(
        top: file.contextCheckpoints, host: nil, for: .claude))
  }

  public func applying(_ edit: PreferenceEdit) -> PreferenceValues {
    var values = self
    switch edit {
    case .armDelay(let value):
      values.armDelay = value
    case .chainedArmDelay(let value):
      values.chainedArmDelay = value
    case .idleSeconds(let value):
      values.idleSeconds = value
    case .graceSeconds(let value):
      values.graceSeconds = value
    case .snoozeMinutes(let minutes):
      values.snoozeMinutes = minutes
    case .checkForUpdates(let enabled):
      values.checkForUpdates = enabled
    case .quitBehavior(let behavior):
      values.quitBehavior = behavior
    case .modeAfterPlan(let mode):
      values.modeAfterPlan = mode
    case .questionNotes(let enabled):
      values.questionNotes = enabled
    case .appearance(let appearance):
      values.appearance = appearance
    case .accentColor(let color):
      values.accentColor = color
    case .addHandoffApp(let bundleID):
      if !values.handoffApps.contains(bundleID) {
        values.handoffApps.append(bundleID)
      }
    case .removeHandoffApp(let bundleID):
      values.handoffApps.removeAll { $0 == bundleID }
    case .editorApp(let bundleID):
      values.editorApp = bundleID
    case .contextCheckpointsEnabled(let enabled):
      values.contextCheckpoints.enabled = enabled
    case .contextMode(let mode):
      values.contextCheckpoints.mode = mode
    case .contextStandardThresholds(let ladder):
      values.contextCheckpoints.standardThresholds = ladder
    case .contextMillionThresholds(let ladder):
      values.contextCheckpoints.millionThresholds = ladder
    case .setContextModelThresholds(let prefix, let ladder):
      values.contextCheckpoints.modelThresholds[prefix] = ladder
    case .removeContextModelThresholds(let prefix):
      values.contextCheckpoints.modelThresholds[prefix] = nil
    case .contextRearmBelow(let ratio):
      values.contextCheckpoints.rearmBelow = ratio
    case .contextHandoffFile(let file):
      values.contextCheckpoints.handoffFile = file
    case .contextNote(let name, let text):
      values.contextCheckpoints.notes.set(text, named: name)
    case .contextMenuBarMeter(let enabled):
      values.contextCheckpoints.menuBarMeter = enabled
    case .reset(let name):
      values = values.applyingDefault(of: name)
    }
    return values
  }

  private func applyingDefault(of name: PreferenceName) -> PreferenceValues {
    var values = self
    switch name {
    case .armDelay: values.armDelay = Settings.defaultArmDelay
    case .chainedArmDelay: values.chainedArmDelay = Settings.defaultChainedArmDelay
    case .idleSeconds: values.idleSeconds = Settings.defaultIdleSeconds
    case .graceSeconds: values.graceSeconds = Settings.defaultGraceSeconds
    case .snoozeMinutes: values.snoozeMinutes = Settings.defaultSnoozeMinutes
    case .handoffApps: values.handoffApps = Settings.defaultHandoffApps
    case .checkForUpdates: values.checkForUpdates = Settings.defaultCheckForUpdates
    case .quitBehavior: values.quitBehavior = Settings.defaultQuitBehavior
    case .modeAfterPlan: values.modeAfterPlan = Settings.defaultModeAfterPlan
    case .questionNotes: values.questionNotes = Settings.defaultQuestionNotes
    case .appearance: values.appearance = Settings.defaultAppearance
    case .accentColor: values.accentColor = Settings.defaultAccentColor
    case .editorApp: values.editorApp = nil
    case .contextCheckpointsEnabled:
      values.contextCheckpoints.enabled = ContextCheckpointSettings.default.enabled
    case .contextMode: values.contextCheckpoints.mode = ContextCheckpointSettings.defaultMode
    case .contextStandardThresholds:
      values.contextCheckpoints.standardThresholds =
        ContextCheckpointSettings.defaultStandardThresholds
    case .contextMillionThresholds:
      values.contextCheckpoints.millionThresholds =
        ContextCheckpointSettings.defaultMillionThresholds
    case .contextModelThresholds: values.contextCheckpoints.modelThresholds = [:]
    case .contextRearmBelow:
      values.contextCheckpoints.rearmBelow = ContextCheckpointSettings.defaultRearmBelow
    case .contextHandoffFile:
      values.contextCheckpoints.handoffFile = ContextCheckpointSettings.defaultHandoffFile
    case .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteCompact,
      .contextNoteHandoff:
      values.contextCheckpoints.notes.set(
        ContextCheckpointNotes.default.text(for: name) ?? "", named: name)
    case .contextMenuBarMeter:
      values.contextCheckpoints.menuBarMeter = ContextCheckpointSettings.default.menuBarMeter
    }
    return values
  }
}
