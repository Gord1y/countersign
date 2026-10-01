import Foundation

public struct Settings: Sendable, Equatable {
  public var armDelay: Double
  public var chainedArmDelay: Double
  public var idleSeconds: Double
  public var graceSeconds: Double
  public var handoffApps: [String]
  public var snoozePresets: [TimeInterval]
  public var quietHours: [QuietWindow]
  public var checkForUpdates: Bool
  public var quitBehavior: QuitBehavior
  public var modeAfterPlan: PlanApprovalMode
  public var panelSound: String
  public var waitingNotices: Bool
  public var waitingNoticeDelay: TimeInterval
  public var approvalCard: Bool
  public var approvalCardDelay: Double
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
    snoozePresets: [TimeInterval],
    quietHours: [QuietWindow] = Settings.defaultQuietHours,
    checkForUpdates: Bool,
    quitBehavior: QuitBehavior,
    modeAfterPlan: PlanApprovalMode,
    panelSound: String = Settings.defaultPanelSound,
    waitingNotices: Bool = Settings.defaultWaitingNotices,
    waitingNoticeDelay: TimeInterval = Settings.defaultWaitingNoticeDelay,
    approvalCard: Bool,
    approvalCardDelay: Double = Settings.defaultApprovalCardDelay,
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
    self.snoozePresets = snoozePresets
    self.quietHours = quietHours
    self.checkForUpdates = checkForUpdates
    self.quitBehavior = quitBehavior
    self.modeAfterPlan = modeAfterPlan
    self.panelSound = panelSound
    self.waitingNotices = waitingNotices
    self.waitingNoticeDelay = waitingNoticeDelay
    self.approvalCard = approvalCard
    self.approvalCardDelay = approvalCardDelay
    self.includeHeadlessSessions = includeHeadlessSessions
    self.questionNotes = questionNotes
    self.appearance = appearance
    self.accentColor = accentColor
    self.contextCheckpoints = contextCheckpoints
  }

  public static let armDelayRange: ClosedRange<Double> = 0...3
  public static let defaultArmDelay: Double = 0.5
  public static let defaultChainedArmDelay: Double = 0.1
  public static let defaultIdleSeconds: Double = 5
  public static let defaultGraceSeconds: Double = 0
  public static let defaultHandoffApps: [String] = []
  public static let idleSecondsRange: ClosedRange<Double> = 1...30
  public static let graceSecondsRange: ClosedRange<Double> = 0...30
  public static let snoozePresetRange: ClosedRange<TimeInterval> = 10...86400
  public static let defaultSnoozePresets: [TimeInterval] = [60, 300, 900, 1800]
  public static let defaultQuietHours: [QuietWindow] = []
  public static let defaultCheckForUpdates = false
  public static let defaultQuitBehavior = QuitBehavior.ask
  public static let defaultModeAfterPlan = PlanApprovalMode.default
  public static let defaultPanelSound = PanelSound.none
  public static let defaultWaitingNotices = true
  public static let defaultWaitingNoticeDelay: TimeInterval = 120
  public static let waitingNoticeDelayRange: ClosedRange<TimeInterval> = 10...3600
  public static let defaultApprovalCardDelay: Double = 5
  public static let approvalCardDelayRange: ClosedRange<Double> = 1...600
  public static let defaultIncludeHeadlessSessions = false
  public static let defaultQuestionNotes = false
  public static let defaultAppearance = AppearanceChoice.system
  public static let defaultAccentColor = AccentPreset.amber.color

  public static func defaultApprovalCard(for host: Host) -> Bool {
    host != .claude
  }

  public static func resolve(file: ConfigFile, host: Host) -> Settings {
    let hostOverrides = file.overrides(for: host)
    let idleSeconds = hostOverrides?.idleSeconds ?? file.idleSeconds ?? defaultIdleSeconds
    let graceSeconds = hostOverrides?.graceSeconds ?? file.graceSeconds ?? defaultGraceSeconds
    let handoffApps = hostOverrides?.handoffApps ?? file.handoffApps ?? defaultHandoffApps
    let armDelay = hostOverrides?.armDelay ?? file.armDelay ?? defaultArmDelay
    let chainedArmDelay =
      hostOverrides?.chainedArmDelay ?? file.chainedArmDelay ?? defaultChainedArmDelay
    let snoozePresets = hostOverrides?.snoozePresets ?? file.snoozePresets ?? defaultSnoozePresets
    let quietHours = file.quietHours ?? defaultQuietHours
    let checkForUpdates = file.checkForUpdates ?? defaultCheckForUpdates
    let quitBehavior = file.quitBehavior ?? defaultQuitBehavior
    let modeAfterPlan = file.modeAfterPlan ?? defaultModeAfterPlan
    let panelSound = file.panelSound ?? defaultPanelSound
    let waitingNotices = file.waitingNotices ?? defaultWaitingNotices
    let waitingNoticeDelay = file.waitingNoticeDelay ?? defaultWaitingNoticeDelay
    let approvalCard =
      hostOverrides?.approvalCard ?? file.approvalCard ?? defaultApprovalCard(for: host)
    let approvalCardDelay =
      hostOverrides?.approvalCardDelay ?? file.approvalCardDelay ?? defaultApprovalCardDelay
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
      snoozePresets: snoozePresets,
      quietHours: quietHours,
      checkForUpdates: checkForUpdates,
      quitBehavior: quitBehavior,
      modeAfterPlan: modeAfterPlan,
      panelSound: panelSound,
      waitingNotices: waitingNotices,
      waitingNoticeDelay: waitingNoticeDelay,
      approvalCard: approvalCard,
      approvalCardDelay: approvalCardDelay,
      includeHeadlessSessions: includeHeadlessSessions,
      questionNotes: questionNotes,
      appearance: appearance,
      accentColor: accentColor,
      contextCheckpoints: ContextCheckpointSettings.resolve(
        top: file.contextCheckpoints, host: file.contextCheckpointsClaude, for: host))
  }
}
