public struct Settings: Sendable, Equatable {
  public var armDelay: Double
  public var chainedArmDelay: Double
  public var idleSeconds: Double
  public var graceSeconds: Double
  public var handoffApps: [String]
  public var snoozeMinutes: [Int]
  public var quietHours: [QuietWindow]
  public var checkForUpdates: Bool
  public var quitBehavior: QuitBehavior
  public var modeAfterPlan: PlanApprovalMode
  public var panelSound: String
  public var includeHeadlessSessions: Bool
  public var questionNotes: Bool
  public var appearance: AppearanceChoice
  public var accentColor: HexColor
  public var contextCheckpoints: ContextCheckpointSettings

  public init(
    armDelay: Double,
    chainedArmDelay: Double,
    idleSeconds: Double,
    graceSeconds: Double,
    handoffApps: [String],
    snoozeMinutes: [Int],
    quietHours: [QuietWindow] = Settings.defaultQuietHours,
    checkForUpdates: Bool,
    quitBehavior: QuitBehavior,
    modeAfterPlan: PlanApprovalMode,
    panelSound: String = Settings.defaultPanelSound,
    includeHeadlessSessions: Bool,
    questionNotes: Bool,
    appearance: AppearanceChoice,
    accentColor: HexColor,
    contextCheckpoints: ContextCheckpointSettings = .default
  ) {
    self.armDelay = armDelay
    self.chainedArmDelay = chainedArmDelay
    self.idleSeconds = idleSeconds
    self.graceSeconds = graceSeconds
    self.handoffApps = handoffApps
    self.snoozeMinutes = snoozeMinutes
    self.quietHours = quietHours
    self.checkForUpdates = checkForUpdates
    self.quitBehavior = quitBehavior
    self.modeAfterPlan = modeAfterPlan
    self.panelSound = panelSound
    self.includeHeadlessSessions = includeHeadlessSessions
    self.questionNotes = questionNotes
    self.appearance = appearance
    self.accentColor = accentColor
    self.contextCheckpoints = contextCheckpoints
  }

  public static let armDelayRange: ClosedRange<Double> = 0...3
  public static let defaultArmDelay: Double = 0.8
  public static let defaultChainedArmDelay: Double = 0.1
  public static let defaultIdleSeconds: Double = 5
  public static let defaultGraceSeconds: Double = 0
  public static let defaultHandoffApps: [String] = []
  public static let defaultSnoozeMinutes: [Int] = [1, 5, 15, 30]
  public static let defaultQuietHours: [QuietWindow] = []
  public static let defaultCheckForUpdates = false
  public static let defaultQuitBehavior = QuitBehavior.ask
  public static let defaultModeAfterPlan = PlanApprovalMode.default
  public static let defaultPanelSound = PanelSound.none
  public static let defaultIncludeHeadlessSessions = false
  public static let defaultQuestionNotes = false
  public static let defaultAppearance = AppearanceChoice.system
  public static let defaultAccentColor = AccentPreset.amber.color

  public static func resolve(file: ConfigFile, host: Host) -> Settings {
    let hostOverrides = file.overrides(for: host)
    let idleSeconds = hostOverrides?.idleSeconds ?? file.idleSeconds ?? defaultIdleSeconds
    let graceSeconds = hostOverrides?.graceSeconds ?? file.graceSeconds ?? defaultGraceSeconds
    let handoffApps = hostOverrides?.handoffApps ?? file.handoffApps ?? defaultHandoffApps
    let armDelay = hostOverrides?.armDelay ?? file.armDelay ?? defaultArmDelay
    let chainedArmDelay =
      hostOverrides?.chainedArmDelay ?? file.chainedArmDelay ?? defaultChainedArmDelay
    let snoozeMinutes = hostOverrides?.snoozeMinutes ?? file.snoozeMinutes ?? defaultSnoozeMinutes
    let quietHours = file.quietHours ?? defaultQuietHours
    let checkForUpdates = file.checkForUpdates ?? defaultCheckForUpdates
    let quitBehavior = file.quitBehavior ?? defaultQuitBehavior
    let modeAfterPlan = file.modeAfterPlan ?? defaultModeAfterPlan
    let panelSound = file.panelSound ?? defaultPanelSound
    let includeHeadlessSessions =
      hostOverrides?.includeHeadlessSessions ?? file.includeHeadlessSessions
      ?? defaultIncludeHeadlessSessions
    let questionNotes = file.questionNotes ?? defaultQuestionNotes
    let appearance = file.appearance ?? defaultAppearance
    let accentColor = file.accentColor ?? defaultAccentColor

    return Settings(
      armDelay: armDelay,
      chainedArmDelay: chainedArmDelay,
      idleSeconds: idleSeconds,
      graceSeconds: graceSeconds,
      handoffApps: handoffApps,
      snoozeMinutes: snoozeMinutes,
      quietHours: quietHours,
      checkForUpdates: checkForUpdates,
      quitBehavior: quitBehavior,
      modeAfterPlan: modeAfterPlan,
      panelSound: panelSound,
      includeHeadlessSessions: includeHeadlessSessions,
      questionNotes: questionNotes,
      appearance: appearance,
      accentColor: accentColor,
      contextCheckpoints: ContextCheckpointSettings.resolve(
        top: file.contextCheckpoints, host: file.contextCheckpointsClaude, for: host))
  }
}
