import Foundation
import Testing

@testable import ApprovalCore

@Suite struct PreferenceValuesTests {
  @Test func appliesEveryContextEdit() {
    var values = PreferenceValues()
    values = values.applying(.contextCheckpointsEnabled(true))
    values = values.applying(.contextMode(.silent))
    values = values.applying(.contextStandardThresholds([1, 2, 3]))
    values = values.applying(.contextMillionThresholds([4, 5, 6]))
    values = values.applying(.setContextModelThresholds(prefix: "claude-opus", ladder: [7, 8, 9]))
    values = values.applying(.setContextModelThresholds(prefix: "claude-haiku", ladder: [1]))
    values = values.applying(.removeContextModelThresholds(prefix: "claude-haiku"))
    values = values.applying(.contextRearmBelow(0.5))
    values = values.applying(.contextHandoffFile("h.md"))
    values = values.applying(.contextNote(.contextNoteSoft, "a"))
    values = values.applying(.contextNote(.contextNoteStatus, "b"))
    values = values.applying(.contextNote(.contextNoteInsist, "c"))
    values = values.applying(.contextNote(.contextNoteCompact, "d"))
    values = values.applying(.contextNote(.contextNoteHandoff, "e"))
    values = values.applying(.contextMenuBarMeter(true))
    #expect(
      values.contextCheckpoints
        == ContextCheckpointSettings(
          enabled: true, mode: .silent, standardThresholds: [1, 2, 3],
          millionThresholds: [4, 5, 6], modelThresholds: ["claude-opus": [7, 8, 9]],
          rearmBelow: 0.5, handoffFile: "h.md",
          notes: ContextCheckpointNotes(
            soft: "a", status: "b", insist: "c", compact: "d", handoff: "e"),
          menuBarMeter: true))
  }

  @Test func resetsEveryContextNameToItsDefault() {
    var values = PreferenceValues()
    values = values.applying(.contextMode(.silent))
    values = values.applying(.contextNote(.contextNoteSoft, "a"))
    values = values.applying(.setContextModelThresholds(prefix: "x", ladder: [1]))
    values = values.applying(.contextMenuBarMeter(true))
    for name in PreferenceName.allCases {
      values = values.applying(.reset(name))
    }
    #expect(values == PreferenceValues())
  }

  @Test func readsTheTopLevelContextBlockFromTheFile() {
    let file = ConfigFile(
      contextCheckpoints: ContextCheckpointFileValues(
        enabled: true, mode: .silent, notes: ["soft": "a"]))
    let settings = PreferenceValues(file: file).contextCheckpoints
    #expect(settings.enabled)
    #expect(settings.mode == .silent)
    #expect(settings.notes.soft == "a")
    #expect(settings.notes.status == ContextCheckpointNotes.default.status)
    #expect(PreferenceValues(file: ConfigFile()).contextCheckpoints == .default)
  }

  @Test func startsFromTheBuiltInDefaults() {
    let values = PreferenceValues()
    #expect(values.armDelay == Settings.defaultArmDelay)
    #expect(values.chainedArmDelay == Settings.defaultChainedArmDelay)
    #expect(values.idleSeconds == Settings.defaultIdleSeconds)
    #expect(values.graceSeconds == Settings.defaultGraceSeconds)
    #expect(values.snoozePresets == Settings.defaultSnoozePresets)
    #expect(values.handoffApps == Settings.defaultHandoffApps)
    #expect(values.checkForUpdates == Settings.defaultCheckForUpdates)
    #expect(values.showSkills == Settings.defaultShowSkills)
    #expect(PreferenceValues(file: ConfigFile(showSkills: false)).showSkills == false)
    #expect(PreferenceValues(file: ConfigFile()).showSkills == true)
    #expect(values.quitBehavior == .ask)
    #expect(values.modeAfterPlan == Settings.defaultModeAfterPlan)
    #expect(values.questionNotes == Settings.defaultQuestionNotes)
    #expect(PreferenceValues(file: ConfigFile()) == values)
  }

  @Test func readsEveryTopLevelKeyFromTheFile() {
    let file = ConfigFile(
      armDelay: 1.5, chainedArmDelay: 0.3, idleSeconds: 8, graceSeconds: 2,
      handoffApps: ["com.x"], snoozePresets: [600], checkForUpdates: true, quitBehavior: .pause,
      modeAfterPlan: .auto, questionNotes: true,
      claude: ConfigFile.HostOverrides(armDelay: 3))
    #expect(
      PreferenceValues(file: file)
        == PreferenceValues(
          armDelay: 1.5, chainedArmDelay: 0.3, idleSeconds: 8, graceSeconds: 2,
          snoozePresets: [600], handoffApps: ["com.x"], checkForUpdates: true,
          quitBehavior: .pause, modeAfterPlan: .auto, questionNotes: true))
  }

  @Test func usesTheDefaultForEveryKeyTheFileLeavesOut() {
    #expect(
      PreferenceValues(file: ConfigFile(graceSeconds: 4, questionNotes: true))
        == PreferenceValues(graceSeconds: 4, questionNotes: true))
    #expect(
      PreferenceValues(file: ConfigFile(quitBehavior: .keepShowing))
        == PreferenceValues(quitBehavior: .keepShowing))
    #expect(
      PreferenceValues(file: ConfigFile(modeAfterPlan: .acceptEdits))
        == PreferenceValues(modeAfterPlan: .acceptEdits))
  }

  @Test func appliesEachEditToItsOwnValue() {
    let values = PreferenceValues()
    #expect(values.applying(.armDelay(1.1)) == PreferenceValues(armDelay: 1.1))
    #expect(values.applying(.chainedArmDelay(0.4)) == PreferenceValues(chainedArmDelay: 0.4))
    #expect(values.applying(.idleSeconds(7)) == PreferenceValues(idleSeconds: 7))
    #expect(values.applying(.graceSeconds(3)) == PreferenceValues(graceSeconds: 3))
    #expect(
      values.applying(.snoozePresets([120, 240])) == PreferenceValues(snoozePresets: [120, 240]))
    #expect(values.applying(.checkForUpdates(true)) == PreferenceValues(checkForUpdates: true))
    #expect(values.applying(.showSkills(false)) == PreferenceValues(showSkills: false))
    #expect(
      PreferenceValues(showSkills: false).applying(.reset(.showSkills)) == PreferenceValues())
    #expect(values.applying(.quitBehavior(.pause)) == PreferenceValues(quitBehavior: .pause))
    #expect(
      values.applying(.modeAfterPlan(.auto)) == PreferenceValues(modeAfterPlan: .auto))
    #expect(values.applying(.questionNotes(true)) == PreferenceValues(questionNotes: true))
    #expect(values.applying(.appearance(.dark)) == PreferenceValues(appearance: .dark))
    #expect(
      values.applying(.accentColor(AccentPreset.green.color))
        == PreferenceValues(accentColor: AccentPreset.green.color))
    #expect(values.applying(.addHandoffApp("com.x")) == PreferenceValues(handoffApps: ["com.x"]))
  }

  @Test func applyingTheShownValueChangesNothing() {
    let values = PreferenceValues(
      armDelay: 1.5, idleSeconds: 8, snoozePresets: [600], handoffApps: ["com.a"],
      quitBehavior: .keepShowing)
    #expect(values.applying(.armDelay(1.5)) == values)
    #expect(values.applying(.idleSeconds(8)) == values)
    #expect(values.applying(.snoozePresets([600])) == values)
    #expect(values.applying(.quitBehavior(.keepShowing)) == values)
    #expect(values.applying(.modeAfterPlan(Settings.defaultModeAfterPlan)) == values)
    #expect(values.applying(.checkForUpdates(Settings.defaultCheckForUpdates)) == values)
    #expect(values.applying(.showSkills(Settings.defaultShowSkills)) == values)
    #expect(values.applying(.addHandoffApp("com.a")) == values)
    #expect(values.applying(.removeHandoffApp("com.b")) == values)
  }

  @Test func resetRestoresTheBuiltInDefaultOfOneName() {
    let values = PreferenceValues(
      armDelay: 1.5, snoozePresets: [600], handoffApps: ["com.a"], quitBehavior: .pause,
      modeAfterPlan: .auto, questionNotes: true)
    #expect(values.applying(.reset(.armDelay)).armDelay == Settings.defaultArmDelay)
    #expect(values.applying(.reset(.snoozeMinutes)).snoozePresets == Settings.defaultSnoozePresets)
    #expect(values.applying(.reset(.handoffApps)).handoffApps == Settings.defaultHandoffApps)
    #expect(values.applying(.reset(.quitBehavior)).quitBehavior == Settings.defaultQuitBehavior)
    #expect(
      values.applying(.reset(.modeAfterPlan)).modeAfterPlan == Settings.defaultModeAfterPlan)
    #expect(values.applying(.reset(.questionNotes)).questionNotes == Settings.defaultQuestionNotes)
    let looks = PreferenceValues(appearance: .light, accentColor: AccentPreset.graphite.color)
    #expect(looks.applying(.reset(.appearance)).appearance == Settings.defaultAppearance)
    #expect(looks.applying(.reset(.accentColor)).accentColor == Settings.defaultAccentColor)
    #expect(
      PreferenceValues(
        file: ConfigFile(appearance: .light, accentColor: AccentPreset.graphite.color))
        == looks)
    #expect(
      values.applying(.reset(.armDelay))
        == PreferenceValues(
          snoozePresets: [600], handoffApps: ["com.a"], quitBehavior: .pause,
          modeAfterPlan: .auto, questionNotes: true))
  }

  @Test func resettingAnAlreadyDefaultNameChangesNothing() {
    #expect(PreferenceValues().applying(.reset(.armDelay)) == PreferenceValues())
  }

  @Test func addsAHandoffAppAtTheEndOnce() {
    let values = PreferenceValues(handoffApps: ["com.a", "com.b"])
    #expect(values.applying(.addHandoffApp("com.c")).handoffApps == ["com.a", "com.b", "com.c"])
    #expect(
      values.applying(.addHandoffApp("com.c")).applying(.addHandoffApp("com.c")).handoffApps
        == ["com.a", "com.b", "com.c"])
  }

  @Test func removesEveryCopyOfAHandoffApp() {
    let values = PreferenceValues(handoffApps: ["com.a", "com.b", "com.a"])
    #expect(values.applying(.removeHandoffApp("com.a")).handoffApps == ["com.b"])
  }

  @Test func eachWrittenEditReadsBackAsTheValuesItShows() throws {
    let original = Array(
      "{\n  \"handoffApps\": [\"com.a\", \"com.b\"],\n  \"idleSeconds\": 5\n}\n".utf8)
    let values = PreferenceValues(file: ConfigFileParser.parse(Data(original)).file)
    let edits: [PreferenceEdit] = [
      .armDelay(1.1), .chainedArmDelay(0), .idleSeconds(12), .graceSeconds(3),
      .snoozePresets([120, 240]), .addHandoffApp("com.c"), .removeHandoffApp("com.a"),
      .checkForUpdates(true), .questionNotes(true), .quitBehavior(.pause),
      .modeAfterPlan(.acceptEdits),
    ]
    for edit in edits {
      let written = try ConfigEdit.applying([edit], to: original)
      let reread = PreferenceValues(file: ConfigFileParser.parse(Data(written)).file)
      #expect(reread == values.applying(edit))
    }
  }

  @Test func writingEditsOneAfterAnotherKeepsEveryEarlierOne() throws {
    var written = Array("{\n  \"handoffApps\": [\"com.a\"],\n  \"idleSeconds\": 5\n}\n".utf8)
    var values = PreferenceValues(file: ConfigFileParser.parse(Data(written)).file)
    for edit: PreferenceEdit in [
      .idleSeconds(12), .removeHandoffApp("com.a"), .addHandoffApp("com.b"),
      .checkForUpdates(true), .quitBehavior(.pause),
    ] {
      written = try ConfigEdit.applying([edit], to: written)
      values = values.applying(edit)
    }
    #expect(
      String(decoding: written, as: UTF8.self)
        == "{\n  \"handoffApps\": [\n    \"com.b\"\n  ],\n  \"idleSeconds\": 12,\n"
        + "  \"checkForUpdates\": true,\n  \"quitBehavior\": \"pause\"\n}\n")
    #expect(PreferenceValues(file: ConfigFileParser.parse(Data(written)).file) == values)
  }
}
