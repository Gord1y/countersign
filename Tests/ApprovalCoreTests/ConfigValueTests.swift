import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ConfigValueTests {
  private func edits(
    _ name: PreferenceName, _ text: String, current: PreferenceValues = PreferenceValues()
  ) -> Result<[PreferenceEdit], ConfigValueError> {
    ConfigValue.edits(for: name, text: text, current: current)
  }

  private func message(_ result: Result<[PreferenceEdit], ConfigValueError>) -> String? {
    if case .failure(let error) = result { return error.description }
    return nil
  }

  @Test func booleansTakeTrueFalseOnAndOff() {
    for text in ["true", "on"] {
      #expect(edits(.showSkills, text) == .success([.showSkills(true)]))
    }
    for text in ["false", "off"] {
      #expect(edits(.showSkills, text) == .success([.showSkills(false)]))
    }
    #expect(message(edits(.showSkills, "maybe")) == "error: expected true, false, on or off")
  }

  @Test func durationsTakeAUnitOrBareSecondsAndKeepTheRange() {
    #expect(edits(.idleSeconds, "5s") == .success([.idleSeconds(5)]))
    #expect(edits(.idleSeconds, "5") == .success([.idleSeconds(5)]))
    #expect(
      message(edits(.idleSeconds, "31"))
        == "error: "
        + DurationFieldError.outOfRange(31, Settings.idleSecondsRange).description)
  }

  @Test func rawValueKeysTakeTheirCasesOnly() {
    let good = QuitBehavior.allCases[0]
    #expect(edits(.quitBehavior, good.rawValue) == .success([.quitBehavior(good)]))
    #expect(message(edits(.quitBehavior, "bogus"))?.hasPrefix("error: expected ") == true)
    #expect(message(edits(.contextMode, "bogus"))?.hasPrefix("error: expected ") == true)
  }

  @Test func steppedNumbersMustSitOnTheirStepInRange() {
    #expect(edits(.keepAwakeBatteryCutoff, "20") == .success([.keepAwakeBatteryCutoff(20)]))
    for text in ["7", "100", "abc"] {
      #expect(
        message(edits(.keepAwakeBatteryCutoff, text)) == "error: expected 5 to 95 in steps of 5")
    }
    #expect(edits(.contextRearmBelow, "25%") == .success([.contextRearmBelow(0.25)]))
    #expect(edits(.contextRearmBelow, "40") == .success([.contextRearmBelow(0.4)]))
    for text in ["12", "10.4", "5", "100", "abc"] {
      #expect(
        message(edits(.contextRearmBelow, text))
          == "error: expected 10 to 95 percent in steps of 5")
    }
  }

  @Test func snoozePresetsUseTheSettingsRules() {
    #expect(edits(.snoozeMinutes, "5, 15m") == .success([.snoozePresets([300, 900])]))
    #expect(
      message(edits(.snoozeMinutes, "abc"))
        == "error: " + SnoozeTextError.notADuration("abc").description)
  }

  @Test func quietHoursTakeWindowsJoinedBySemicolons() throws {
    let weekdays = try #require(QuietWindow(days: [.mon, .tue], from: "22:00", to: "07:00"))
    let saturday = try #require(QuietWindow(days: [.sat], from: "9", to: "12"))
    #expect(
      edits(.quietHours, "mon,tue 22:00-07:00; sat 9-12")
        == .success([.quietHours([weekdays, saturday])]))
    #expect(edits(.quietHours, "none") == .success([.quietHours([])]))
    #expect(message(edits(.quietHours, "funday 9-12"))?.contains("funday") == true)
    #expect(
      message(edits(.quietHours, "mon 25-12"))
        == "error: " + QuietWindowError.badTimes.description)
    #expect(
      message(edits(.quietHours, "mon 9-12; mon 9-12"))
        == "error: " + QuietWindowError.duplicate.description)
  }

  @Test func handoffAppsRemoveWhatIsNotListedAndAddWhatIsNew() {
    var current = PreferenceValues()
    current.handoffApps = ["a.b", "c.d"]
    #expect(
      edits(.handoffApps, "c.d, e.f", current: current)
        == .success([.removeHandoffApp("a.b"), .addHandoffApp("e.f")]))
    #expect(
      edits(.handoffApps, "none", current: current)
        == .success([.removeHandoffApp("a.b"), .removeHandoffApp("c.d")]))
  }

  @Test func modelThresholdsSetListedPrefixesAndRemoveTheRest() {
    var current = PreferenceValues()
    current.contextCheckpoints.modelThresholds = ["old": [100_000, 200_000]]
    #expect(
      edits(.contextModelThresholds, "new=50,150; keep=100,200", current: current)
        == .success([
          .removeContextModelThresholds(prefix: "old"),
          .setContextModelThresholds(prefix: "keep", ladder: [100_000, 200_000]),
          .setContextModelThresholds(prefix: "new", ladder: [50_000, 150_000]),
        ]))
    #expect(
      edits(.contextModelThresholds, "none", current: current)
        == .success([.removeContextModelThresholds(prefix: "old")]))
    #expect(
      message(edits(.contextModelThresholds, "noequals"))
        == "error: expected <prefix>=<ladder>, like claude-opus-5=200,400")
    #expect(
      message(edits(.contextModelThresholds, "new=50,150; new=60,160"))
        == "error: \"new\" is listed twice")
    #expect(
      message(edits(.contextModelThresholds, "x=5")) == "error: "
        + ContextTextError.ladder.description)
  }

  @Test func choicesPutTheFirstOneFirst() {
    #expect(
      edits(.contextSoftChoices, "handoff, continue")
        == .success([.contextChoices(.contextSoftChoices, [.handOff, .continueWorking])]))
    let shape =
      "error: expected 1 to 4 different choices from compact, handoff, continue and mute"
    #expect(message(edits(.contextSoftChoices, "bogus")) == shape)
    #expect(message(edits(.contextSoftChoices, "compact, compact")) == shape)
  }

  @Test func theThreeHookAndOptInKeysAreRefusedWithTheirReasons() {
    let reasons: [PreferenceName: String] = [
      .keepAwake: "it needs its explanation first",
      .waitingNotices: "it changes your agents' hook files",
      .contextCheckpointsEnabled: "it changes your agents' hook files",
    ]
    for (name, reason) in reasons {
      #expect(edits(name, "true") == .failure(.refused(name)))
      #expect(
        ConfigValueError.refused(name).description
          == "error: \(name.commandLineKey) can only be changed in Settings (\(name.title)): \(reason)"
      )
    }
    #expect(ConfigValue.resetRefusal(.waitingNotices) == .refused(.waitingNotices))
    #expect(
      ConfigValue.resetRefusal(.contextCheckpointsEnabled) == .refused(.contextCheckpointsEnabled))
    #expect(ConfigValue.resetRefusal(.keepAwake) == nil)
  }

  @Test func approvalCardTakesOnOffOrAListOfAgents() {
    func expected(_ listed: [ApprovalCore.Host]) -> Result<[PreferenceEdit], ConfigValueError> {
      .success(ApprovalCore.Host.allCases.map { .forAgent($0, .approvalCard(listed.contains($0))) })
    }
    #expect(edits(.approvalCard, "on") == expected(ApprovalCore.Host.allCases))
    #expect(edits(.approvalCard, "off") == expected([]))
    #expect(edits(.approvalCard, "claude, codex") == expected([.claude, .codex]))
    #expect(message(edits(.approvalCard, "bogus"))?.contains("\"bogus\"") == true)
  }

  @Test func everyKeyThatCanBeSetReadsBackWhatItPrints() throws {
    let values = PreferenceValues()
    for name in PreferenceName.allCases where ConfigValue.refusal(name) == nil {
      let text = ConfigValue.text(name, values: values)
      let result = edits(name, text, current: values)
      let applied = try result.get().reduce(values) { $0.applying($1) }
      #expect(applied == values, "\(name.commandLineKey) = \(text)")
    }
  }

  private func customValues() throws -> PreferenceValues {
    var values = PreferenceValues()
    values.quietHours = [
      try #require(QuietWindow(days: [.mon, .tue], from: "22:00", to: "07:00")),
      try #require(QuietWindow(days: [.sat], from: "9", to: "12")),
    ]
    values.handoffApps = ["com.example.one", "com.example.two"]
    values.editorApp = "com.example.editor"
    values.approvalCardAgents = [.codex]
    values.snoozePresets = [60, 600]
    values.accentColor = try #require(HexColor(hex: "#123ABC"))
    values.contextCheckpoints.modelThresholds = [
      "claude-opus-5": [100_000, 200_000], "claude-haiku": [50_000, 150_000],
    ]
    values.contextCheckpoints.choices.soft = [.handOff, .compactAfterStep]
    values.contextCheckpoints.choices.status = [.notThisSession, .continueWorking]
    values.contextCheckpoints.choices.insist = [.compactAfterStep]
    values.contextCheckpoints.notes.soft = "A custom soft note."
    values.contextCheckpoints.handoffFile = "~/notes/handoff.md"
    return values
  }

  @Test func everyListKeyRoundTripsThroughTheFile() throws {
    let values = try customValues()
    #expect(values.approvalCardAgents != PreferenceValues.defaultApprovalCardAgents)
    var allEdits: [PreferenceEdit] = []
    for name in PreferenceName.allCases where ConfigValue.refusal(name) == nil {
      let text = ConfigValue.text(name, values: values)
      let result = edits(name, text, current: PreferenceValues())
      allEdits += try result.get()
    }
    let written = try ConfigEdit.applying(allEdits, to: nil)
    let reloaded = PreferenceValues(file: ConfigFileParser.parse(Data(written)).file)
    #expect(reloaded == values)
  }

  @Test func noPaneResetsAKeyThatChangesHookFiles() {
    for pane in SettingsPane.allCases {
      for name in pane.preferenceNames {
        #expect(ConfigValue.resetRefusal(name) == nil, "\(pane.rawValue): \(name.commandLineKey)")
      }
    }
  }
}
