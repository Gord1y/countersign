import Testing

@testable import ApprovalCore

@Suite struct PreferenceOverridesTests {
  @Test func namesNoValuesWithoutABlock() {
    #expect(PreferenceOverrides.values(in: nil) == [])
    #expect(PreferenceOverrides.values(in: ConfigFile.HostOverrides()) == [])
  }

  @Test func namesEveryValueInThePanelsOrder() {
    let overrides = ConfigFile.HostOverrides(
      armDelay: 1, chainedArmDelay: 0.2, idleSeconds: 2, graceSeconds: 3,
      handoffApps: ["com.openai.codex", "com.todesktop.cursor"], snoozePresets: [300, 3600],
      includeHeadlessSessions: true)
    #expect(
      PreferenceOverrides.values(in: overrides) == [
        "wait for idle 2 s", "grace period 3 s", "arm delay 1 s", "arm delay after an answer 0.2 s",
        "hand off when frontmost com.openai.codex, com.todesktop.cursor",
        "snooze presets 5, 60 min", "headless sessions on",
      ])
  }

  @Test func namesSubMinuteSnoozePresetsWithTheirUnits() {
    let overrides = ConfigFile.HostOverrides(snoozePresets: [30, 300])
    #expect(PreferenceOverrides.values(in: overrides) == ["snooze presets 30s, 5"])
  }

  @Test func namesAnEmptyHandoffListAndHeadlessSessionsOff() {
    let overrides = ConfigFile.HostOverrides(handoffApps: [], includeHeadlessSessions: false)
    #expect(
      PreferenceOverrides.values(in: overrides) == [
        "hand off when frontmost none", "headless sessions off",
      ])
  }

  @Test func writesNoNoteForAHostWithoutOwnValues() {
    #expect(PreferenceOverrides.note(for: .claude, in: ConfigFile()) == nil)
    let codexOnly = ConfigFile(codex: ConfigFile.HostOverrides(graceSeconds: 3))
    #expect(PreferenceOverrides.note(for: .claude, in: codexOnly) == nil)
    #expect(
      PreferenceOverrides.note(for: .claude, in: ConfigFile(claude: ConfigFile.HostOverrides()))
        == nil)
  }

  @Test func writesOneNotePerHostFromItsOwnBlock() {
    let file = ConfigFile(
      graceSeconds: 0,
      claude: ConfigFile.HostOverrides(graceSeconds: 3),
      codex: ConfigFile.HostOverrides(idleSeconds: 1, snoozePresets: [60, 300]),
      cursor: ConfigFile.HostOverrides(armDelay: 0.5),
      antigravity: ConfigFile.HostOverrides(chainedArmDelay: 0))
    #expect(
      PreferenceOverrides.note(for: .claude, in: file)
        == "Own values in config.json: grace period 3 s")
    #expect(
      PreferenceOverrides.note(for: .codex, in: file)
        == "Own values in config.json: wait for idle 1 s; snooze presets 1, 5 min")
    #expect(
      PreferenceOverrides.note(for: .cursor, in: file)
        == "Own values in config.json: arm delay 0.5 s")
    #expect(
      PreferenceOverrides.note(for: .antigravity, in: file)
        == "Own values in config.json: arm delay after an answer 0 s")
  }

  @Test func namesTheTopLevelKeysOnlyTheFileSets() {
    #expect(
      PreferenceOverrides.fileOnlyTopLevelKeys == ["includeHeadlessSessions"])
    #expect(
      PreferenceOverrides.fileOnlyNote
        == "Only the file can set values for one agent, under hosts, and includeHeadlessSessions.")
  }

  @Test func fileOnlyNoteListsEveryKeyOrNone() {
    #expect(
      PreferenceOverrides.fileOnlyNote(keys: [])
        == "Only the file can set values for one agent, under hosts.")
    #expect(
      PreferenceOverrides.fileOnlyNote(keys: ["a", "b"])
        == "Only the file can set values for one agent, under hosts, and a, b.")
  }
}
