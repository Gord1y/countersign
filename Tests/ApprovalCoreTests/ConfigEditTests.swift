import Foundation
import Testing

@testable import ApprovalCore

private let schema = SettingsPrompt.schemaURL

private func editing(_ text: String?, _ edits: PreferenceEdit...) throws -> String {
  let bytes = try ConfigEdit.applying(edits, to: text.map { Array($0.utf8) })
  return String(decoding: bytes, as: UTF8.self)
}

@Suite struct ConfigEditTests {
  @Test func createsTheStarterFileFirstWhenMissing() throws {
    #expect(
      try editing(nil, .armDelay(1.2))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"armDelay\": 1.2\n}\n")
    #expect(
      try editing(" \n", .checkForUpdates(true))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"checkForUpdates\": true\n}\n")
  }

  @Test func touchesOnlyTheChangedKey() throws {
    let config = "{\n  \"idleSeconds\": 5,\n  \"graceSeconds\": 1, \"armDelay\":0.50\n}\n"
    #expect(
      try editing(config, .graceSeconds(2))
        == "{\n  \"idleSeconds\": 5,\n  \"graceSeconds\": 2, \"armDelay\":0.50\n}\n")
    #expect(
      try editing(config, .idleSeconds(12.5))
        == "{\n  \"idleSeconds\": 12.5,\n  \"graceSeconds\": 1, \"armDelay\":0.50\n}\n")
  }

  @Test func keepsAValueThatAlreadyHoldsTheChoice() throws {
    let config = "{\"armDelay\": 0.80, \"snoozeMinutes\": [5, 10], \"checkForUpdates\": false}"
    #expect(
      try editing(config, .armDelay(0.8), .snoozePresets([300, 600]), .checkForUpdates(false))
        == config)
  }

  @Test func writesADefaultValueExplicitly() throws {
    #expect(
      try editing("{\n  \"armDelay\": 1\n}\n", .graceSeconds(0))
        == "{\n  \"armDelay\": 1,\n  \"graceSeconds\": 0\n}\n")
  }

  @Test func writesTheChainedArmDelay() throws {
    #expect(
      try editing(nil, .chainedArmDelay(0.1))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"chainedArmDelay\": 0.1\n}\n")
    #expect(
      try editing("{\n  \"armDelay\": 1\n}\n", .chainedArmDelay(0.3))
        == "{\n  \"armDelay\": 1,\n  \"chainedArmDelay\": 0.3\n}\n")
    #expect(
      try editing("{\"chainedArmDelay\": 0.3, \"armDelay\": 1}", .chainedArmDelay(0))
        == "{\"chainedArmDelay\": 0, \"armDelay\": 1}")
    #expect(
      try editing("{\n  \"chainedArmDelay\": \"fast\"\n}\n", .chainedArmDelay(2))
        == "{\n  \"chainedArmDelay\": 2\n}\n")
  }

  @Test func keepsAChainedArmDelayThatAlreadyHoldsTheChoice() throws {
    let config = "{\"chainedArmDelay\": 0.10, \"armDelay\": 0.8}"
    #expect(try editing(config, .chainedArmDelay(0.1), .armDelay(0.8)) == config)
  }

  @Test func replacesAValueOfTheWrongType() throws {
    #expect(
      try editing("{\n  \"idleSeconds\": \"5\"\n}\n", .idleSeconds(7))
        == "{\n  \"idleSeconds\": 7\n}\n")
  }

  @Test func writesSnoozePresetsAndTheUpdateCheck() throws {
    #expect(
      try editing("{\n  \"snoozeMinutes\": [5, 10]\n}\n", .snoozePresets([60, 3600]))
        == "{\n  \"snoozeMinutes\": [\n    1,\n    60\n  ]\n}\n")
    #expect(
      try editing("{\n  \"checkForUpdates\": false\n}\n", .checkForUpdates(true))
        == "{\n  \"checkForUpdates\": true\n}\n")
  }

  @Test func writesSubMinuteSnoozePresetsAsUnitStrings() throws {
    #expect(
      try editing("{\n  \"snoozeMinutes\": [5, 10]\n}\n", .snoozePresets([30, 300]))
        == "{\n  \"snoozeMinutes\": [\n    \"30s\",\n    5\n  ]\n}\n")
  }

  @Test func keepsSnoozePresetsThatAlreadyHoldTheChoiceInAnyUnit() throws {
    let config = "{\"snoozeMinutes\": [\"30s\", 5, \"15m\"]}"
    #expect(try editing(config, .snoozePresets([30, 300, 900])) == config)
  }

  @Test func writesTheWaitingNoticeDelayAsABareNumberOfSeconds() throws {
    #expect(
      try editing("{\"waitingNoticeDelay\": 5}", .waitingNoticeDelay(10))
        == "{\"waitingNoticeDelay\": 10}")
    #expect(
      try editing("{\"waitingNoticeDelay\": 5}", .waitingNoticeDelay(90))
        == "{\"waitingNoticeDelay\": 90}")
    let config = "{\"waitingNoticeDelay\": \"2m\"}"
    #expect(try editing(config, .waitingNoticeDelay(120)) == config)
  }

  @Test func writesSecondsKeysWithUpToThreeDecimals() throws {
    #expect(
      try editing("{\"armDelay\": 1}", .armDelay(0.2504)) == "{\"armDelay\": 0.25}")
    #expect(
      try editing("{\"graceSeconds\": 1}", .graceSeconds(0.5)) == "{\"graceSeconds\": 0.5}")
  }

  @Test func writesTheQuitBehavior() throws {
    #expect(
      try editing(nil, .quitBehavior(.pause))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"quitBehavior\": \"pause\"\n}\n")
    #expect(
      try editing("{\n  \"idleSeconds\": 5\n}\n", .quitBehavior(.keepShowing))
        == "{\n  \"idleSeconds\": 5,\n  \"quitBehavior\": \"keepShowing\"\n}\n")
    #expect(
      try editing("{\"quitBehavior\": \"pause\", \"idleSeconds\": 5}", .quitBehavior(.ask))
        == "{\"quitBehavior\": \"ask\", \"idleSeconds\": 5}")
    #expect(
      try editing("{\n  \"quitBehavior\": true\n}\n", .quitBehavior(.pause))
        == "{\n  \"quitBehavior\": \"pause\"\n}\n")
  }

  @Test func keepsAQuitBehaviorThatAlreadyHoldsTheChoice() throws {
    let config = "{\"quitBehavior\":\"keepShowing\"}"
    #expect(try editing(config, .quitBehavior(.keepShowing)) == config)
  }

  @Test func writesTheModeAfterPlan() throws {
    #expect(
      try editing(nil, .modeAfterPlan(.acceptEdits))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"modeAfterPlan\": \"acceptEdits\"\n}\n")
    #expect(
      try editing("{\n  \"idleSeconds\": 5\n}\n", .modeAfterPlan(.auto))
        == "{\n  \"idleSeconds\": 5,\n  \"modeAfterPlan\": \"auto\"\n}\n")
    #expect(
      try editing("{\"modeAfterPlan\": \"auto\", \"idleSeconds\": 5}", .modeAfterPlan(.default))
        == "{\"modeAfterPlan\": \"default\", \"idleSeconds\": 5}")
    #expect(
      try editing("{\n  \"modeAfterPlan\": true\n}\n", .modeAfterPlan(.acceptEdits))
        == "{\n  \"modeAfterPlan\": \"acceptEdits\"\n}\n")
  }

  @Test func keepsAModeAfterPlanThatAlreadyHoldsTheChoice() throws {
    let config = "{\"modeAfterPlan\":\"acceptEdits\"}"
    #expect(try editing(config, .modeAfterPlan(.acceptEdits)) == config)
  }

  @Test func writesQuestionNotes() throws {
    #expect(
      try editing(nil, .questionNotes(true))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"questionNotes\": true\n}\n")
    #expect(
      try editing("{\n  \"questionNotes\": true\n}\n", .questionNotes(false))
        == "{\n  \"questionNotes\": false\n}\n")
    #expect(
      try editing("{\"questionNotes\": false}", .questionNotes(false))
        == "{\"questionNotes\": false}"
    )
  }

  @Test func writesTheAppearanceAndAccentColor() throws {
    #expect(
      try editing(nil, .appearance(.dark))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"appearance\": \"dark\"\n}\n")
    #expect(
      try editing("{\"appearance\": \"dark\"}", .appearance(.system))
        == "{\"appearance\": \"system\"}")
    #expect(
      try editing("{\n  \"idleSeconds\": 5\n}\n", .accentColor(AccentPreset.blue.color))
        == "{\n  \"idleSeconds\": 5,\n  \"accentColor\": \"#5B9CF6\"\n}\n")
    #expect(
      try editing("{\"accentColor\": 3}", .accentColor(HexColor(red: 0x0A, green: 0x0B, blue: 0)))
        == "{\"accentColor\": \"#0A0B00\"}")
  }

  @Test func keepsAnAppearanceOrAccentColorThatAlreadyHoldsTheChoice() throws {
    let config = "{\"appearance\":\"light\", \"accentColor\": \"#5b9cf6\"}"
    #expect(
      try editing(config, .appearance(.light), .accentColor(AccentPreset.blue.color)) == config)
  }

  @Test func resetRemovesTheAppearanceAndAccentColor() throws {
    #expect(
      try editing(
        "{\"appearance\": \"dark\", \"accentColor\": \"#5B9CF6\", \"idleSeconds\": 8}",
        .reset(.appearance), .reset(.accentColor))
        == "{\"idleSeconds\": 8}")
  }

  @Test func writesTheEditorApp() throws {
    #expect(
      try editing(nil, .editorApp("com.x"))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"editorApp\": \"com.x\"\n}\n")
    #expect(
      try editing("{\n  \"idleSeconds\": 5\n}\n", .editorApp("com.x"))
        == "{\n  \"idleSeconds\": 5,\n  \"editorApp\": \"com.x\"\n}\n")
    #expect(
      try editing("{\"editorApp\": \"com.x\", \"idleSeconds\": 5}", .editorApp("com.y"))
        == "{\"editorApp\": \"com.y\", \"idleSeconds\": 5}")
    #expect(
      try editing("{\n  \"editorApp\": 3\n}\n", .editorApp("com.x"))
        == "{\n  \"editorApp\": \"com.x\"\n}\n")
  }

  @Test func keepsAnEditorAppThatAlreadyHoldsTheChoice() throws {
    let config = "{\"editorApp\": \"com.x\"}"
    #expect(try editing(config, .editorApp("com.x")) == config)
  }

  @Test func resetRemovesTheEditorAppKey() throws {
    #expect(try editing("{\n  \"editorApp\": \"com.x\"\n}\n", .reset(.editorApp)) == "{}\n")
  }

  @Test func keepsTheFilesOwnLayout() throws {
    let config = "{\r\n    \"idleSeconds\" : 5\r\n}\r\n"
    #expect(
      try editing(config, .checkForUpdates(true))
        == "{\r\n    \"idleSeconds\" : 5,\r\n    \"checkForUpdates\" : true\r\n}\r\n")
  }

  @Test func addsAHandoffApp() throws {
    #expect(
      try editing("{\n  \"armDelay\": 1\n}\n", .addHandoffApp("com.x"))
        == "{\n  \"armDelay\": 1,\n  \"handoffApps\": [\n    \"com.x\"\n  ]\n}\n")
    #expect(
      try editing("{\n  \"handoffApps\": [\n    \"com.x\"\n  ]\n}\n", .addHandoffApp("com.y"))
        == "{\n  \"handoffApps\": [\n    \"com.x\",\n    \"com.y\"\n  ]\n}\n")
    #expect(
      try editing("{\"handoffApps\": [\"com.x\", \"com.y\"]}", .addHandoffApp("com.z"))
        == "{\"handoffApps\": [\"com.x\", \"com.y\", \"com.z\"]}")
    #expect(
      try editing("{\n  \"handoffApps\": []\n}\n", .addHandoffApp("com.x"))
        == "{\n  \"handoffApps\": [\n    \"com.x\"\n  ]\n}\n")
  }

  @Test func leavesAHandoffAppThatIsAlreadyListed() throws {
    let config = "{\"handoffApps\": [\"com.x\"]}"
    #expect(try editing(config, .addHandoffApp("com.x")) == config)
  }

  @Test func replacesHandoffAppsThatAreNotAListOfStrings() throws {
    #expect(
      try editing("{\n  \"handoffApps\": \"com.x\"\n}\n", .addHandoffApp("com.y"))
        == "{\n  \"handoffApps\": [\n    \"com.y\"\n  ]\n}\n")
    #expect(
      try editing("{\n  \"handoffApps\": [\"com.x\", 3]\n}\n", .addHandoffApp("com.y"))
        == "{\n  \"handoffApps\": [\n    \"com.y\"\n  ]\n}\n")
  }

  @Test func removesAHandoffApp() throws {
    #expect(
      try editing(
        "{\n  \"handoffApps\": [\n    \"com.x\",\n    \"com.y\",\n    \"com.x\"\n  ]\n}\n",
        .removeHandoffApp("com.x"))
        == "{\n  \"handoffApps\": [\n    \"com.y\"\n  ]\n}\n")
    #expect(
      try editing("{\n  \"handoffApps\": [\n    \"com.x\"\n  ]\n}\n", .removeHandoffApp("com.x"))
        == "{\n  \"handoffApps\": []\n}\n")
  }

  @Test func removingAnUnlistedAppChangesNothing() throws {
    let listed = "{\"handoffApps\": [\"com.x\"]}"
    #expect(try editing(listed, .removeHandoffApp("com.y")) == listed)
    #expect(try editing("{}", .removeHandoffApp("com.y")) == "{}")
    #expect(
      try editing("{\"handoffApps\": 3}", .removeHandoffApp("com.y")) == "{\"handoffApps\": 3}")
  }

  @Test func resetRemovesTheTopLevelKey() throws {
    #expect(try editing("{\n  \"idleSeconds\": 8\n}\n", .reset(.idleSeconds)) == "{}\n")
    #expect(
      try editing("{\"idleSeconds\": 8, \"graceSeconds\": 3}", .reset(.idleSeconds))
        == "{\"graceSeconds\": 3}")
    #expect(
      try editing("{\"graceSeconds\": 3, \"idleSeconds\": 8}", .reset(.idleSeconds))
        == "{\"graceSeconds\": 3}")
    #expect(
      try editing("{\"a\": 1, \"idleSeconds\": 8, \"b\": 2}", .reset(.idleSeconds))
        == "{\"a\": 1, \"b\": 2}")
  }

  @Test func resettingAnAbsentKeyChangesNothing() throws {
    #expect(try editing("{}", .reset(.idleSeconds)) == "{}")
    #expect(
      try editing(nil, .reset(.idleSeconds))
        == "{\n  \"$schema\": \"\(schema)\"\n}\n")
  }

  @Test func resetKeepsTheFilesOwnLayout() throws {
    let config = "{\r\n  \"armDelay\": 1,\r\n  \"idleSeconds\": 8\r\n}\r\n"
    #expect(try editing(config, .reset(.idleSeconds)) == "{\r\n  \"armDelay\": 1\r\n}\r\n")
  }

  @Test func resetNeverTouchesHostsOrSchema() throws {
    let config =
      "{\"$schema\": \"x\", \"idleSeconds\": 8, \"hosts\": {\"claude\": {\"idleSeconds\": 3}}}"
    #expect(
      try editing(config, .reset(.idleSeconds))
        == "{\"$schema\": \"x\", \"hosts\": {\"claude\": {\"idleSeconds\": 3}}}")
  }

  @Test func appliesSeveralEditsInOrder() throws {
    #expect(
      try editing("{}\n", .addHandoffApp("com.x"), .removeHandoffApp("com.x"), .idleSeconds(3))
        == "{\n  \"handoffApps\": [],\n  \"idleSeconds\": 3\n}\n")
  }

  @Test func refusesAFileItCannotEdit() {
    #expect(throws: JSONSpanError(line: 1, column: 3)) {
      try ConfigEdit.applying([.idleSeconds(3)], to: Array("{ nope".utf8))
    }
    #expect(
      throws: HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    ) {
      try ConfigEdit.applying([.idleSeconds(3)], to: Array("[]".utf8))
    }
  }

  @Test func namesTheProblemWithAFile() {
    #expect(ConfigEdit.problem(in: nil) == nil)
    #expect(ConfigEdit.problem(in: Array("{}".utf8)) == nil)
    #expect(ConfigEdit.problem(in: Array("{ nope".utf8)) == "not valid JSON at line 1, column 3")
    #expect(ConfigEdit.problem(in: Array("3".utf8)) == "the top level is not an object")
  }

  @Test func namesTheKeyEachEditWrites() {
    #expect(PreferenceEdit.armDelay(1).key == .armDelay)
    #expect(PreferenceEdit.chainedArmDelay(1).key == .chainedArmDelay)
    #expect(PreferenceEdit.idleSeconds(1).key == .idleSeconds)
    #expect(PreferenceEdit.graceSeconds(1).key == .graceSeconds)
    #expect(PreferenceEdit.snoozePresets([60]).key == .snoozeMinutes)
    #expect(PreferenceEdit.waitingNoticeDelay(120).key == .waitingNoticeDelay)
    #expect(PreferenceEdit.checkForUpdates(true).key == .checkForUpdates)
    #expect(PreferenceEdit.quitBehavior(.ask).key == .quitBehavior)
    #expect(PreferenceEdit.modeAfterPlan(.auto).key == .modeAfterPlan)
    #expect(PreferenceEdit.questionNotes(true).key == .questionNotes)
    #expect(PreferenceEdit.appearance(.dark).key == .appearance)
    #expect(PreferenceEdit.accentColor(AccentPreset.blue.color).key == .accentColor)
    #expect(PreferenceEdit.addHandoffApp("a").key == .handoffApps)
    #expect(PreferenceEdit.removeHandoffApp("a").key == .handoffApps)
    #expect(PreferenceEdit.editorApp("com.x").key == .editorApp)
    #expect(PreferenceEdit.reset(.idleSeconds).key == .idleSeconds)
  }

  @Test func eachPreferenceNameIsATopLevelKeyOfTheFile() {
    #expect(
      PreferenceName.allCases.prefix(14).map(\.rawValue) == [
        "armDelay", "chainedArmDelay", "idleSeconds", "graceSeconds", "snoozeMinutes",
        "quietHours", "handoffApps", "checkForUpdates", "questionNotes", "quitBehavior",
        "modeAfterPlan", "appearance", "accentColor", "editorApp",
      ])
    #expect(
      PreferenceName.allCases.prefix(14).allSatisfy { $0.keyPath == [$0.rawValue] })
    #expect(
      Set(PreferenceName.allCases.compactMap(\.keyPath.first)).isSubset(
        of: ConfigFileParser.topLevelKeys))
  }

  @Test func namesTheKeyPathOfEveryContextRow() {
    #expect(
      PreferenceName.allCases.suffix(13).map { $0.keyPath.joined(separator: ".") } == [
        "contextCheckpoints.enabled", "contextCheckpoints.mode",
        "contextCheckpoints.thresholds.200k", "contextCheckpoints.thresholds.1m",
        "contextCheckpoints.modelThresholds", "contextCheckpoints.rearmBelow",
        "contextCheckpoints.handoffFile", "contextCheckpoints.notes.soft",
        "contextCheckpoints.notes.status", "contextCheckpoints.notes.insist",
        "contextCheckpoints.notes.compact", "contextCheckpoints.notes.handoff",
        "contextCheckpoints.menuBarMeter",
      ])
  }

  @Test func enablingCreatesTheBlockInTheFilesStyle() throws {
    #expect(
      try editing(nil, .contextCheckpointsEnabled(true))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"contextCheckpoints\": {\n    \"enabled\": true\n  }\n}\n"
    )
    #expect(
      try editing("{\n\t\"armDelay\": 1\n}\n", .contextCheckpointsEnabled(true))
        == "{\n\t\"armDelay\": 1,\n\t\"contextCheckpoints\": {\n\t\t\"enabled\": true\n\t}\n}\n")
  }

  @Test func settingTheMillionLadderCreatesThresholdsInAnExistingBlock() throws {
    let config = "{\n  \"contextCheckpoints\": {\n    \"enabled\": true\n  }\n}\n"
    #expect(
      try editing(config, .contextMillionThresholds([250_000, 350_000, 450_000]))
        == "{\n  \"contextCheckpoints\": {\n    \"enabled\": true,\n    \"thresholds\": {\n"
        + "      \"1m\": [\n        250000,\n        350000,\n        450000\n      ]\n    }\n  }\n}\n"
    )
  }

  @Test func keepsALadderThatAlreadyHoldsTheChoice() throws {
    let config =
      "{\"contextCheckpoints\": {\"thresholds\": {\"200k\": [100000.0, 130000, 160000]}}}"
    #expect(try editing(config, .contextStandardThresholds([100_000, 130_000, 160_000])) == config)
  }

  @Test func aNoteEditKeepsItsSiblings() throws {
    let config =
      "{\n  \"contextCheckpoints\": {\n    \"notes\": {\n      \"soft\": \"a\",\n      \"status\": \"b\"\n    }\n  }\n}\n"
    #expect(
      try editing(config, .contextNote(.contextNoteStatus, "c"))
        == "{\n  \"contextCheckpoints\": {\n    \"notes\": {\n      \"soft\": \"a\",\n      \"status\": \"c\"\n    }\n  }\n}\n"
    )
    #expect(
      try editing(config, .contextNote(.contextNoteInsist, "d"))
        == "{\n  \"contextCheckpoints\": {\n    \"notes\": {\n      \"soft\": \"a\",\n      \"status\": \"b\",\n      \"insist\": \"d\"\n    }\n  }\n}\n"
    )
  }

  @Test func ignoresANoteEditForAnyOtherName() throws {
    let config = "{\n  \"armDelay\": 1\n}\n"
    #expect(try editing(config, .contextNote(.armDelay, "x")) == config)
  }

  @Test func removingAModelLadderReturnsTheBytesBeforeTheSet() throws {
    let config =
      "{\n  \"contextCheckpoints\": {\n    \"modelThresholds\": {\n      \"claude-opus\": [\n        1,\n        2,\n        3\n      ]\n    }\n  }\n}\n"
    let withPrefix = try editing(
      config, .setContextModelThresholds(prefix: "claude-sonnet", ladder: [10, 20, 30]))
    #expect(withPrefix != config)
    #expect(withPrefix.contains("\"claude-sonnet\""))
    #expect(
      try editing(withPrefix, .removeContextModelThresholds(prefix: "claude-sonnet")) == config)
  }

  @Test func resettingTheModeRemovesOnlyTheMode() throws {
    let config =
      "{\n  \"contextCheckpoints\": {\n    \"enabled\": true,\n    \"mode\": \"silent\",\n    \"rearmBelow\": 0.5\n  }\n}\n"
    #expect(
      try editing(config, .reset(.contextMode))
        == "{\n  \"contextCheckpoints\": {\n    \"enabled\": true,\n    \"rearmBelow\": 0.5\n  }\n}\n"
    )
  }

  @Test func resettingTheOnlyMemberLeavesAnEmptyObject() throws {
    let config = "{\n  \"contextCheckpoints\": {\n    \"mode\": \"silent\"\n  }\n}\n"
    let result = try editing(config, .reset(.contextMode))
    let parsed = ConfigFileParser.parse(Data(result.utf8)).file
    #expect(parsed.contextCheckpoints != nil)
    #expect(parsed.contextCheckpoints?.mode == nil)
    #expect(try editing("{}", .reset(.contextMode)) == "{}")
    #expect(
      try editing("{\"contextCheckpoints\": 3}", .reset(.contextMode))
        == "{\"contextCheckpoints\": 3}")
  }

  @Test func neverTouchesTheContextCheckpointHosts() throws {
    let hosts = "\"hosts\": {\n      \"claude\": {\n        \"mode\": \"silent\"\n      }\n    }"
    let config = "{\n  \"contextCheckpoints\": {\n    \(hosts)\n  }\n}\n"
    let result = try editing(
      config, .contextMode(.silent), .contextRearmBelow(0.5), .reset(.contextMode),
      .contextNote(.contextNoteSoft, "x"))
    #expect(result.contains(hosts))
    let untouched = try editing(config, .reset(.contextMode))
    #expect(untouched == config)
  }

  @Test func replacesAContextBlockOfTheWrongType() throws {
    #expect(
      try editing("{\n  \"contextCheckpoints\": 3\n}\n", .contextMode(.silent))
        == "{\n  \"contextCheckpoints\": {\n    \"mode\": \"silent\"\n  }\n}\n")
  }

  @Test func spellsNumbersLikeTheEditor() {
    #expect(ConfigEdit.spelling(3) == "3")
    #expect(ConfigEdit.spelling(0.5) == "0.5")
    #expect(ConfigEdit.spelling(0.8) == "0.8")
  }
}
