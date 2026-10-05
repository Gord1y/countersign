import Testing

@testable import ApprovalCore

@Suite struct SettingsPaneTests {
  @Test func listsTheSevenGroupsInOrder() {
    #expect(
      SettingsPane.allCases == [.agents, .panels, .app, .rules, .context, .help, .advanced])
    #expect(
      SettingsPane.allCases.map(\.rawValue) == [
        "agents", "panels", "app", "rules", "context", "help", "advanced",
      ])
    #expect(
      SettingsPane.allCases.map(\.title) == [
        "Agents", "Panels", "App", "Rules", "Context", "Help", "Advanced",
      ])
  }

  @Test func saysWhatTheRulesGroupDoes() {
    #expect(SettingsPane.rules.title == "Rules")
    #expect(SettingsPane.rules.subtitle == "Allow or deny requests before a panel shows.")
    #expect(SettingsPane.rules.preferenceNames.isEmpty)
  }

  @Test func saysWhatTheContextGroupChanges() {
    #expect(
      SettingsPane.context.subtitle
        == "Context checkpoints for Claude Code sessions. Saved to config.json as soon as you"
        + " change them.")
  }

  @Test func showsTheContextGroupOnlyWhenAsked() {
    #expect(
      SettingsPane.sidebar(showsContext: true) == [
        .agents, .app, .panels, .rules, .context, .help,
      ])
    #expect(
      SettingsPane.sidebar(showsContext: false) == [.agents, .app, .panels, .rules, .help])
    #expect(SettingsPane.sidebar == SettingsPane.sidebar(showsContext: false))
  }

  @Test func saysWhatEachGroupChangesAndWhereItIsKept() {
    #expect(
      SettingsPane.agents.subtitle
        == "Which coding agents Countersign answers for. Changes each agent's own hook file,"
        + " after showing you the change.")
    #expect(
      SettingsPane.panels.subtitle
        == "How approval panels behave. Saved to config.json as soon as you"
        + " change them.")
    #expect(
      SettingsPane.app.subtitle == "What the menu-bar app does, and how panels and Settings look.")
    #expect(
      SettingsPane.help.subtitle
        == "Guides and answers, updates, and ways to support Countersign.")
    #expect(
      SettingsPane.advanced.subtitle
        == "Where your settings are stored, and what only the file can set.")
  }

  @Test func listsTheSidebarGroupsInOrder() {
    #expect(SettingsPane.sidebar == [.agents, .app, .panels, .rules, .help])
  }

  @Test func keepsAdvancedOutOfTheSidebar() {
    #expect(!SettingsPane.sidebar.contains(.advanced))
  }

  @Test func opensOnAgents() {
    #expect(SettingsPane.standard == .agents)
  }

  @Test func namesThePreferencesEachGroupWrites() {
    #expect(
      SettingsPane.panels.preferenceNames == [
        .idleSeconds, .graceSeconds, .armDelay, .chainedArmDelay, .snoozeMinutes, .quietHours,
        .handoffApps, .questionNotes, .modeAfterPlan, .panelSound,
        .waitingNoticeDelay, .waitingNoticeDuration, .approvalCard, .approvalCardDelay,
      ])
    #expect(
      SettingsPane.app.preferenceNames == [
        .checkForUpdates, .quitBehavior, .appearance, .accentColor,
      ])
    #expect(SettingsPane.agents.preferenceNames == [])
    #expect(SettingsPane.help.preferenceNames.isEmpty)
    #expect(SettingsPane.advanced.preferenceNames == [])
    #expect(
      SettingsPane.context.preferenceNames == [
        .contextMode, .contextStandardThresholds, .contextMillionThresholds,
        .contextModelThresholds, .contextRearmBelow, .contextHandoffFile, .contextNoteSoft,
        .contextNoteStatus, .contextNoteInsist, .contextNoteCompact, .contextNoteHandoff,
        .contextMenuBarMeter,
      ])
    #expect(
      Set(
        SettingsPane.panels.preferenceNames + SettingsPane.app.preferenceNames
          + SettingsPane.context.preferenceNames)
        == Set(PreferenceName.allCases).subtracting([
          .editorApp, .contextCheckpointsEnabled, .waitingNotices,
        ]))
  }
}
