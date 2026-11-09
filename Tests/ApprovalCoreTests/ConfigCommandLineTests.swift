import Testing

@testable import ApprovalCore

@Suite struct ConfigCommandLineTests {
  @Test func getAloneListsEverySetting() {
    #expect(ConfigCommandLine.parse(["get"]) == .list)
  }

  @Test func getWithAKeyGivesThatSetting() {
    #expect(ConfigCommandLine.parse(["get", "idleSeconds"]) == .get(.idleSeconds))
    #expect(
      ConfigCommandLine.parse(["get", "contextCheckpoints.thresholds.200k"])
        == .get(.contextStandardThresholds))
  }

  @Test func setTakesExactlyOneValueArgument() {
    #expect(ConfigCommandLine.parse(["set", "idleSeconds", "5s"]) == .set(.idleSeconds, "5s"))
    #expect(
      ConfigCommandLine.parse(["set", "quietHours", "mon 22:00-07:00; sat 9-12"])
        == .set(.quietHours, "mon 22:00-07:00; sat 9-12"))
  }

  @Test func resetTakesAKeyOrAPane() {
    #expect(ConfigCommandLine.parse(["reset", "idleSeconds"]) == .reset(.idleSeconds))
    #expect(ConfigCommandLine.parse(["reset", "--pane", "panels"]) == .resetPane(.panels))
  }

  @Test func openTakesNothing() {
    #expect(ConfigCommandLine.parse(["open"]) == .open)
  }

  @Test func anyOtherShapeIsNil() {
    let shapes = [
      [], ["bogus"], ["get", "a", "b"], ["set", "idleSeconds"], ["set"], ["reset"],
      ["reset", "--pane"], ["open", "x"], ["set", "idleSeconds", "1", "2"],
    ]
    for shape in shapes {
      #expect(ConfigCommandLine.parse(shape) == nil, "\(shape)")
    }
  }

  @Test func anUnknownKeyOrPaneIsNamed() {
    #expect(ConfigCommandLine.parse(["get", "nope"]) == .unknownKey("nope"))
    #expect(ConfigCommandLine.parse(["set", "nope", "1"]) == .unknownKey("nope"))
    #expect(ConfigCommandLine.parse(["reset", "nope"]) == .unknownKey("nope"))
    #expect(ConfigCommandLine.parse(["reset", "--pane", "nope"]) == .unknownPane("nope"))
  }

  @Test func everySettingRoundTripsThroughItsKey() {
    for name in PreferenceName.allCases {
      #expect(PreferenceName(commandLineKey: name.commandLineKey) == name)
    }
  }
}
