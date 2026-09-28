import Foundation

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
    editorApp: String? = nil
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
      editorApp: file.editorApp)
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
    }
    return values
  }
}
