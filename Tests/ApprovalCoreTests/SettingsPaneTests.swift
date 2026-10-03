import Testing

@testable import ApprovalCore

@Suite struct SettingsPaneTests {
  @Test func listsTheSixGroupsInOrder() {
    #expect(SettingsPane.allCases == [.agents, .panels, .app, .context, .help, .advanced])
    #expect(
      SettingsPane.allCases.map(\.rawValue) == [
        "agents", "panels", "app", "context", "help", "advanced",
      ])
    #expect(
      SettingsPane.allCases.map(\.title) == [
        "Agents", "Panels", "App", "Context", "Help", "Advanced",
      ])
  }

  @Test func saysWhatTheContextGroupChanges() {
    #expect(
      SettingsPane.context.subtitle
        == "Context checkpoints for Claude Code sessions. Saved to config.json as soon as you"
        + " change them.")
  }

  @Test func showsTheContextGroupOnlyWhenAsked() {
    #expect(SettingsPane.sidebar(showsContext: true) == [.agents, .app, .panels, .context, .help])
    #expect(SettingsPane.sidebar(showsContext: false) == [.agents, .app, .panels, .help])
    #expect(SettingsPane.sidebar == SettingsPane.sidebar(showsContext: false))
  }

  @Test func fallsBackToAgentsForAStoredContextGroupWhenHidden() {
    #expect(SettingsPane(storedValue: "context", showsContext: true) == .context)
    #expect(SettingsPane(storedValue: "context", showsContext: false) == .agents)
    #expect(SettingsPane(storedValue: "panels", showsContext: false) == .panels)
    #expect(SettingsPane(storedValue: nil, showsContext: true) == .agents)
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
    #expect(SettingsPane.sidebar == [.agents, .app, .panels, .help])
  }

  @Test func keepsAdvancedOutOfTheSidebar() {
    #expect(!SettingsPane.sidebar.contains(.advanced))
  }

  @Test func readsAStoredGroupAndFallsBackToAgents() {
    #expect(SettingsPane.standard == .agents)
    #expect(SettingsPane(storedValue: "panels") == .panels)
    #expect(SettingsPane(storedValue: "help") == .help)
    #expect(SettingsPane(storedValue: "advanced") == .advanced)
    #expect(SettingsPane(storedValue: nil) == .agents)
    #expect(SettingsPane(storedValue: "") == .agents)
    #expect(SettingsPane(storedValue: "Panels") == .agents)
    #expect(SettingsPane(storedValue: "preferences") == .agents)
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
