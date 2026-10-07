import Testing

@testable import ApprovalCore

@Suite struct SettingsTests {
  @Test func resolvesBuiltInDefaultsFromAnEmptyFile() {
    let settings = Settings.resolve(file: ConfigFile(), host: .claude)
    #expect(settings.armDelay == Settings.defaultArmDelay)
    #expect(settings.chainedArmDelay == Settings.defaultChainedArmDelay)
    #expect(settings.idleSeconds == Settings.defaultIdleSeconds)
    #expect(settings.graceSeconds == Settings.defaultGraceSeconds)
    #expect(settings.handoffApps == Settings.defaultHandoffApps)
    #expect(settings.snoozePresets == Settings.defaultSnoozePresets)
    #expect(settings.checkForUpdates == Settings.defaultCheckForUpdates)
    #expect(settings.showSkills == Settings.defaultShowSkills)
    #expect(settings.quitBehavior == .ask)
    #expect(settings.modeAfterPlan == Settings.defaultModeAfterPlan)
    #expect(settings.includeHeadlessSessions == Settings.defaultIncludeHeadlessSessions)
    #expect(settings.questionNotes == Settings.defaultQuestionNotes)
    #expect(settings.appearance == .system)
    #expect(settings.accentColor == AccentPreset.amber.color)
  }

  @Test func topLevelValuesOverrideBuiltInDefaults() {
    let file = ConfigFile(
      armDelay: 1.5, chainedArmDelay: 0.4, idleSeconds: 10, graceSeconds: 2,
      handoffApps: ["com.apple.Terminal"], snoozePresets: [120, 240], checkForUpdates: true,
      quitBehavior: .pause, modeAfterPlan: .acceptEdits, includeHeadlessSessions: true,
      questionNotes: true, appearance: .light, accentColor: AccentPreset.pink.color)
    let settings = Settings.resolve(file: file, host: .claude)
    #expect(settings.appearance == .light)
    #expect(settings.accentColor == AccentPreset.pink.color)
    #expect(settings.armDelay == 1.5)
    #expect(settings.chainedArmDelay == 0.4)
    #expect(settings.idleSeconds == 10)
    #expect(settings.graceSeconds == 2)
    #expect(settings.handoffApps == ["com.apple.Terminal"])
    #expect(settings.snoozePresets == [120, 240])
    #expect(settings.checkForUpdates == true)
    #expect(settings.quitBehavior == .pause)
    #expect(settings.modeAfterPlan == .acceptEdits)
    #expect(settings.includeHeadlessSessions == true)
    #expect(settings.questionNotes == true)
  }

  @Test func hostOverrideWinsOverTopLevel() {
    let file = ConfigFile(
      armDelay: 1.5, chainedArmDelay: 0.2, idleSeconds: 10,
      claude: ConfigFile.HostOverrides(armDelay: 2.5, chainedArmDelay: 0.6, idleSeconds: 20))
    let claudeSettings = Settings.resolve(file: file, host: .claude)
    #expect(claudeSettings.armDelay == 2.5)
    #expect(claudeSettings.chainedArmDelay == 0.6)
    #expect(claudeSettings.idleSeconds == 20)

    let codexSettings = Settings.resolve(file: file, host: .codex)
    #expect(codexSettings.armDelay == 1.5)
    #expect(codexSettings.chainedArmDelay == 0.2)
    #expect(codexSettings.idleSeconds == 10)
  }

  @Test func cursorReadsItsOwnHostBlock() {
    let file = ConfigFile(
      idleSeconds: 10, handoffApps: ["com.apple.Terminal"],
      claude: ConfigFile.HostOverrides(idleSeconds: 20),
      cursor: ConfigFile.HostOverrides(idleSeconds: 30))
    let settings = Settings.resolve(file: file, host: .cursor)
    #expect(settings.idleSeconds == 30)
    #expect(settings.handoffApps == ["com.apple.Terminal"])
  }

  @Test func antigravityReadsItsOwnHostBlock() {
    let file = ConfigFile(
      idleSeconds: 10, handoffApps: ["com.apple.Terminal"],
      cursor: ConfigFile.HostOverrides(idleSeconds: 30),
      antigravity: ConfigFile.HostOverrides(idleSeconds: 40, handoffApps: []))
    let settings = Settings.resolve(file: file, host: .antigravity)
    #expect(settings.idleSeconds == 40)
    #expect(settings.handoffApps == [])
    #expect(Settings.resolve(file: file, host: .cursor).idleSeconds == 30)
  }

  @Test func chainedArmDelayDefaultsToATenthOfASecond() {
    #expect(Settings.defaultChainedArmDelay == 0.1)
    #expect(Settings.resolve(file: ConfigFile(), host: .codex).chainedArmDelay == 0.1)
  }

  @Test func chainedArmDelayIsItsOwnSettingNotTheArmDelay() {
    let file = ConfigFile(armDelay: 2, claude: ConfigFile.HostOverrides(armDelay: 3))
    #expect(Settings.resolve(file: file, host: .claude).chainedArmDelay == 0.1)
    let chainedOnly = ConfigFile(chainedArmDelay: 0)
    let settings = Settings.resolve(file: chainedOnly, host: .claude)
    #expect(settings.chainedArmDelay == 0)
    #expect(settings.armDelay == Settings.defaultArmDelay)
  }

  @Test func checkForUpdatesIsTopLevelOnlyAndIgnoresHostOverrides() {
    let file = ConfigFile(checkForUpdates: true)
    let settings = Settings.resolve(file: file, host: .claude)
    #expect(settings.checkForUpdates == true)
  }

  @Test func showSkillsIsTopLevelOnlyAndIgnoresHostOverrides() {
    let file = ConfigFile(showSkills: false)
    let settings = Settings.resolve(file: file, host: .claude)
    #expect(settings.showSkills == false)
  }

  @Test func quitBehaviorIsTopLevelOnly() {
    let file = ConfigFile(quitBehavior: .keepShowing)
    #expect(Settings.resolve(file: file, host: .codex).quitBehavior == .keepShowing)
  }

  @Test func modeAfterPlanIsTopLevelOnly() {
    let file = ConfigFile(modeAfterPlan: .auto)
    #expect(Settings.resolve(file: file, host: .codex).modeAfterPlan == .auto)
  }

  @Test func questionNotesIsTopLevelOnlyAndDefaultsToFalse() {
    let file = ConfigFile(questionNotes: true)
    #expect(Settings.resolve(file: file, host: .claude).questionNotes == true)
    #expect(Settings.resolve(file: file, host: .codex).questionNotes == true)
    #expect(Settings.resolve(file: ConfigFile(), host: .claude).questionNotes == false)
  }

  @Test func graceSecondsUsesHostThenTopLevel() {
    let file = ConfigFile(
      idleSeconds: 4, graceSeconds: 3, claude: ConfigFile.HostOverrides(graceSeconds: 7))
    let claudeSettings = Settings.resolve(file: file, host: .claude)
    #expect(claudeSettings.graceSeconds == 7)
    #expect(claudeSettings.idleSeconds == 4)
    #expect(Settings.resolve(file: file, host: .codex).graceSeconds == 3)
  }

  @Test func handoffAppsUsesTheHostListWholeRatherThanMerging() {
    let file = ConfigFile(
      handoffApps: ["com.apple.Terminal", "com.apple.dt.Xcode"],
      codex: ConfigFile.HostOverrides(handoffApps: ["com.openai.codex"]))
    #expect(Settings.resolve(file: file, host: .codex).handoffApps == ["com.openai.codex"])
    #expect(
      Settings.resolve(file: file, host: .claude).handoffApps
        == ["com.apple.Terminal", "com.apple.dt.Xcode"])
  }

  @Test func armDelayUsesHostThenTopLevel() {
    let file = ConfigFile(armDelay: 1, claude: ConfigFile.HostOverrides(armDelay: 2))
    #expect(Settings.resolve(file: file, host: .claude).armDelay == 2)
    #expect(Settings.resolve(file: file, host: .codex).armDelay == 1)
  }

  @Test func chainedArmDelayUsesHostThenTopLevel() {
    let file = ConfigFile(
      chainedArmDelay: 0.5, codex: ConfigFile.HostOverrides(chainedArmDelay: 0.3))
    #expect(Settings.resolve(file: file, host: .codex).chainedArmDelay == 0.3)
    #expect(Settings.resolve(file: file, host: .claude).chainedArmDelay == 0.5)
  }

  @Test func snoozePresetsUseHostThenTopLevel() {
    let file = ConfigFile(
      snoozePresets: [60, 120], codex: ConfigFile.HostOverrides(snoozePresets: [180, 240]))
    let settings = Settings.resolve(file: file, host: .codex)
    #expect(settings.snoozePresets == [180, 240])
  }

  @Test func includeHeadlessSessionsHostOverrideWinsOverTopLevel() {
    let file = ConfigFile(
      includeHeadlessSessions: false,
      codex: ConfigFile.HostOverrides(includeHeadlessSessions: true))
    let settings = Settings.resolve(file: file, host: .codex)
    #expect(settings.includeHeadlessSessions == true)
  }
}
