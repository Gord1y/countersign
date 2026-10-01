import Testing

@testable import ApprovalCore

@Suite struct PreferenceResetTests {
  @Test func detectsAChangedNumber() {
    #expect(PreferenceReset.isChanged(.idleSeconds, in: ConfigFile(idleSeconds: 8)))
    #expect(!PreferenceReset.isChanged(.idleSeconds, in: ConfigFile(idleSeconds: 5)))
    #expect(!PreferenceReset.isChanged(.idleSeconds, in: ConfigFile()))
  }

  @Test func detectsAChangedList() {
    #expect(PreferenceReset.isChanged(.snoozeMinutes, in: ConfigFile(snoozePresets: [120, 600])))
    #expect(
      !PreferenceReset.isChanged(
        .snoozeMinutes, in: ConfigFile(snoozePresets: [60, 300, 900, 1800])))
    #expect(PreferenceReset.isChanged(.handoffApps, in: ConfigFile(handoffApps: ["com.x"])))
    #expect(!PreferenceReset.isChanged(.handoffApps, in: ConfigFile(handoffApps: [])))
  }

  @Test func detectsAChangedContextLadderNoteAndModelMap() {
    func file(_ values: ContextCheckpointFileValues) -> ConfigFile {
      ConfigFile(contextCheckpoints: values)
    }
    #expect(
      PreferenceReset.isChanged(
        .contextStandardThresholds,
        in: file(ContextCheckpointFileValues(standardThresholds: [90_000, 120_000, 150_000]))))
    #expect(
      !PreferenceReset.isChanged(
        .contextStandardThresholds,
        in: file(ContextCheckpointFileValues(standardThresholds: [100_000, 130_000, 160_000]))))
    #expect(!PreferenceReset.isChanged(.contextStandardThresholds, in: ConfigFile()))
    #expect(
      PreferenceReset.isChanged(
        .contextNoteSoft, in: file(ContextCheckpointFileValues(notes: ["soft": "mine"]))))
    #expect(
      !PreferenceReset.isChanged(
        .contextNoteSoft,
        in: file(ContextCheckpointFileValues(notes: ["soft": ContextCheckpointNotes.default.soft])))
    )
    #expect(
      !PreferenceReset.isChanged(
        .contextNoteStatus, in: file(ContextCheckpointFileValues(notes: ["soft": "mine"]))))
    #expect(
      PreferenceReset.isChanged(
        .contextModelThresholds,
        in: file(ContextCheckpointFileValues(modelThresholds: ["claude-opus": [1, 2, 3]]))))
    #expect(
      !PreferenceReset.isChanged(
        .contextModelThresholds, in: file(ContextCheckpointFileValues(modelThresholds: [:]))))
    #expect(
      PreferenceReset.isChanged(
        .contextCheckpointsEnabled, in: file(ContextCheckpointFileValues(enabled: true))))
    #expect(
      !PreferenceReset.isChanged(
        .contextCheckpointsEnabled, in: file(ContextCheckpointFileValues(enabled: false))))
    #expect(
      PreferenceReset.isChanged(
        .contextMode, in: file(ContextCheckpointFileValues(mode: .silent))))
    #expect(
      !PreferenceReset.isChanged(
        .contextMode, in: file(ContextCheckpointFileValues(mode: .panel))))
    #expect(
      PreferenceReset.isChanged(
        .contextRearmBelow, in: file(ContextCheckpointFileValues(rearmBelow: 0.5))))
    #expect(
      !PreferenceReset.isChanged(
        .contextRearmBelow, in: file(ContextCheckpointFileValues(rearmBelow: 0.6))))
    #expect(
      PreferenceReset.isChanged(
        .contextHandoffFile, in: file(ContextCheckpointFileValues(handoffFile: "h.md"))))
    #expect(
      PreferenceReset.isChanged(
        .contextMenuBarMeter, in: file(ContextCheckpointFileValues(menuBarMeter: true))))
    #expect(
      PreferenceReset.isChanged(
        .contextMillionThresholds,
        in: file(ContextCheckpointFileValues(millionThresholds: [1, 2, 3]))))
  }

  @Test func neverCountsAContextNameAsSetForOneAgent() {
    let file = ConfigFile(claude: ConfigFile.HostOverrides(armDelay: 1))
    #expect(!PreferenceReset.hasHostValues(for: SettingsPane.context.preferenceNames, in: file))
  }

  @Test func writesContextValueTextSamples() {
    var values = PreferenceValues()
    #expect(PreferenceReset.valueText(.contextCheckpointsEnabled, in: values) == "Off")
    #expect(PreferenceReset.valueText(.contextMode, in: values) == "Panel")
    #expect(PreferenceReset.valueText(.contextStandardThresholds, in: values) == "100K, 130K, 160K")
    #expect(PreferenceReset.valueText(.contextMillionThresholds, in: values) == "200K, 300K, 400K")
    #expect(PreferenceReset.valueText(.contextModelThresholds, in: values) == "none")
    #expect(PreferenceReset.valueText(.contextRearmBelow, in: values) == "60%")
    #expect(PreferenceReset.valueText(.contextHandoffFile, in: values) == "notes/handoff.md")
    #expect(PreferenceReset.valueText(.contextNoteSoft, in: values) == "Default")
    #expect(PreferenceReset.valueText(.contextMenuBarMeter, in: values) == "Off")
    values = values.applying(.contextCheckpointsEnabled(true)).applying(.contextMode(.silent))
    values = values.applying(.contextNote(.contextNoteSoft, "mine"))
    values = values.applying(.setContextModelThresholds(prefix: "a", ladder: [1]))
    #expect(PreferenceReset.valueText(.contextModelThresholds, in: values) == "1 model")
    values = values.applying(.setContextModelThresholds(prefix: "b", ladder: [1]))
    #expect(PreferenceReset.valueText(.contextModelThresholds, in: values) == "2 models")
    #expect(PreferenceReset.valueText(.contextCheckpointsEnabled, in: values) == "On")
    #expect(PreferenceReset.valueText(.contextMode, in: values) == "Silent")
    #expect(PreferenceReset.valueText(.contextNoteSoft, in: values) == "Custom")
    #expect(
      PreferenceReset.line(for: .contextMode, current: values)
        == "Checkpoint style: Silent → Panel")
  }

  @Test func detectsAChangedBoolAndQuitBehavior() {
    #expect(PreferenceReset.isChanged(.checkForUpdates, in: ConfigFile(checkForUpdates: true)))
    #expect(!PreferenceReset.isChanged(.checkForUpdates, in: ConfigFile(checkForUpdates: false)))
    #expect(PreferenceReset.isChanged(.quitBehavior, in: ConfigFile(quitBehavior: .pause)))
    #expect(!PreferenceReset.isChanged(.quitBehavior, in: ConfigFile(quitBehavior: .ask)))
    #expect(
      PreferenceReset.isChanged(.modeAfterPlan, in: ConfigFile(modeAfterPlan: .acceptEdits)))
    #expect(
      !PreferenceReset.isChanged(.modeAfterPlan, in: ConfigFile(modeAfterPlan: .default)))
  }

  @Test func detectsAChangedAppearanceAndAccentColor() {
    #expect(PreferenceReset.isChanged(.appearance, in: ConfigFile(appearance: .light)))
    #expect(!PreferenceReset.isChanged(.appearance, in: ConfigFile(appearance: .system)))
    #expect(!PreferenceReset.isChanged(.appearance, in: ConfigFile()))
    #expect(
      PreferenceReset.isChanged(.accentColor, in: ConfigFile(accentColor: AccentPreset.blue.color)))
    #expect(
      !PreferenceReset.isChanged(
        .accentColor, in: ConfigFile(accentColor: AccentPreset.amber.color)))
    #expect(!PreferenceReset.isChanged(.accentColor, in: ConfigFile()))
  }

  @Test func detectsAChangedEditorApp() {
    #expect(PreferenceReset.isChanged(.editorApp, in: ConfigFile(editorApp: "com.x")))
    #expect(!PreferenceReset.isChanged(.editorApp, in: ConfigFile()))
  }

  @Test func filtersChangedNamesInOrder() {
    let file = ConfigFile(armDelay: 1, idleSeconds: 8)
    #expect(
      PreferenceReset.changedNames(
        in: file, within: [.idleSeconds, .graceSeconds, .armDelay, .chainedArmDelay])
        == [.idleSeconds, .armDelay])
    #expect(PreferenceReset.changedNames(in: ConfigFile(), within: [.idleSeconds]) == [])
  }

  @Test func linesFormatEveryKind() {
    let values = PreferenceValues(
      armDelay: 1, chainedArmDelay: 0.3, idleSeconds: 8, graceSeconds: 2,
      snoozePresets: [120, 600], handoffApps: ["com.x", "com.y"], checkForUpdates: true,
      quitBehavior: .pause, modeAfterPlan: .acceptEdits, questionNotes: true, appearance: .dark,
      accentColor: AccentPreset.blue.color)
    #expect(PreferenceReset.line(for: .armDelay, current: values) == "Arm delay: 1 s → 0.5 s")
    #expect(PreferenceReset.line(for: .appearance, current: values) == "Appearance: Dark → System")
    #expect(
      PreferenceReset.line(for: .accentColor, current: values) == "Accent colour: Blue → Amber")
    #expect(
      PreferenceReset.line(
        for: .accentColor,
        current: PreferenceValues(accentColor: HexColor(red: 0x12, green: 0x34, blue: 0x56)))
        == "Accent colour: #123456 → Amber")
    #expect(
      PreferenceReset.line(for: .chainedArmDelay, current: values)
        == "Arm delay after an answer: 0.3 s → 0.1 s")
    #expect(PreferenceReset.line(for: .idleSeconds, current: values) == "Wait for idle: 8 s → 5 s")
    #expect(PreferenceReset.line(for: .graceSeconds, current: values) == "Grace period: 2 s → 0 s")
    #expect(
      PreferenceReset.line(for: .snoozeMinutes, current: values)
        == "Snooze presets: 2, 10 → 1, 5, 15, 30")
    #expect(
      PreferenceReset.line(for: .handoffApps, current: values)
        == "Hand off when frontmost: 2 apps → none")
    #expect(
      PreferenceReset.line(for: .checkForUpdates, current: values)
        == "Check for updates: On → Off")
    #expect(
      PreferenceReset.line(for: .questionNotes, current: values) == "Notes on answers: On → Off")
    #expect(
      PreferenceReset.line(for: .quitBehavior, current: values)
        == "When Countersign quits: Pause panels → Ask")
    #expect(
      PreferenceReset.line(for: .modeAfterPlan, current: values)
        == "Mode after a plan: Accept edits → Ask before edits")
  }

  @Test func namesASingleAppWithoutAnS() {
    let values = PreferenceValues(handoffApps: ["com.x"])
    #expect(
      PreferenceReset.line(for: .handoffApps, current: values)
        == "Hand off when frontmost: 1 app → none")
  }

  @Test func addsTheHostsNoteOnlyWhenAGroupKeyIsOverridden() {
    let panelsGroup = SettingsPane.panels.preferenceNames
    let appGroup = SettingsPane.app.preferenceNames
    let file = ConfigFile(idleSeconds: 8, claude: ConfigFile.HostOverrides(idleSeconds: 2))
    #expect(
      PreferenceReset.confirmationLines(
        changed: PreferenceReset.changedNames(in: file, within: panelsGroup), group: panelsGroup,
        current: PreferenceValues(file: file), file: file)
        == ["Wait for idle: 8 s → 5 s", PreferenceReset.hostsNote])
    #expect(
      !PreferenceReset.confirmationLines(
        changed: PreferenceReset.changedNames(in: file, within: appGroup), group: appGroup,
        current: PreferenceValues(file: file), file: file
      ).contains(PreferenceReset.hostsNote))
  }

  @Test func addsTheHostsNoteEvenWhenTheOverriddenKeyItselfIsNotChanged() {
    let panelsGroup = SettingsPane.panels.preferenceNames
    let file = ConfigFile(
      idleSeconds: 8, claude: ConfigFile.HostOverrides(graceSeconds: 3))
    #expect(
      PreferenceReset.confirmationLines(
        changed: PreferenceReset.changedNames(in: file, within: panelsGroup), group: panelsGroup,
        current: PreferenceValues(file: file), file: file)
        == ["Wait for idle: 8 s → 5 s", PreferenceReset.hostsNote])
  }

  @Test func namesNoHostsNoteWithoutAnyOverride() {
    let file = ConfigFile(idleSeconds: 8)
    #expect(
      PreferenceReset.hasHostValues(for: SettingsPane.panels.preferenceNames, in: file) == false)
  }

  @Test func questionNotesAndAppKeysNeverTriggerTheHostsNote() {
    let file = ConfigFile(
      questionNotes: true, claude: ConfigFile.HostOverrides(includeHeadlessSessions: true))
    #expect(!PreferenceReset.hasHostValues(for: [.questionNotes], in: file))
    #expect(!PreferenceReset.hasHostValues(for: SettingsPane.app.preferenceNames, in: file))
  }
}
