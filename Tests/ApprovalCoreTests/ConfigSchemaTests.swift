import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ConfigSchemaTests {
  private static var schemaURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/config.schema.json")
  }

  private static func loadSchema() throws -> JSONValue {
    let data = try Data(contentsOf: schemaURL)
    return try JSONDecoder().decode(JSONValue.self, from: data)
  }

  @Test func topLevelPropertiesMatchTheKeysTheParserKnows() throws {
    let schema = try Self.loadSchema()
    guard case .object(let properties)? = schema["properties"] else {
      Issue.record("schema has no top-level \"properties\" object")
      return
    }
    #expect(Set(properties.keys) == ConfigFileParser.topLevelKeys)
  }

  @Test func hostBlockPropertiesMatchTheKeysTheParserKnows() throws {
    let schema = try Self.loadSchema()
    guard case .object(let hostOverrides)? = schema["$defs"]?["hostOverrides"],
      case .object(let properties)? = hostOverrides["properties"]
    else {
      Issue.record("schema has no \"$defs.hostOverrides.properties\" object")
      return
    }
    #expect(Set(properties.keys) == ConfigFileParser.hostKeys)
  }

  @Test func contextCheckpointPropertiesMatchTheKeysTheParserKnows() throws {
    let schema = try Self.loadSchema()
    guard case .object(let definition)? = schema["$defs"]?["contextCheckpoints"],
      case .object(let properties)? = definition["properties"]
    else {
      Issue.record("schema has no \"$defs.contextCheckpoints.properties\" object")
      return
    }
    #expect(Set(properties.keys) == ConfigFileParser.contextCheckpointKeys)
    #expect(
      properties["hosts"]?["properties"]?["claude"]?["$ref"]?.stringValue
        == "#/$defs/contextCheckpointValues")
    guard
      case .object(let hostProperties)? = schema["$defs"]?["contextCheckpointValues"]?["properties"]
    else {
      Issue.record("schema has no \"$defs.contextCheckpointValues.properties\" object")
      return
    }
    #expect(
      Set(hostProperties.keys) == ConfigFileParser.contextCheckpointKeys.subtracting(["hosts"]))
  }

  @Test func everyHostReferencesTheHostOverridesDefinition() throws {
    let schema = try Self.loadSchema()
    guard case .object(let hosts)? = schema["properties"]?["hosts"],
      case .object(let hostProperties)? = hosts["properties"]
    else {
      Issue.record("schema has no \"properties.hosts.properties\" object")
      return
    }
    #expect(Set(hostProperties.keys) == Set(ApprovalCore.Host.allCases.map(\.rawValue)))
    for host in ApprovalCore.Host.allCases {
      #expect(hostProperties[host.rawValue]?["$ref"]?.stringValue == "#/$defs/hostOverrides")
    }
  }

  @Test func quitBehaviorListsTheChoicesTheParserKnows() throws {
    let schema = try Self.loadSchema()
    guard case .array(let choices)? = schema["properties"]?["quitBehavior"]?["enum"] else {
      Issue.record("schema has no \"properties.quitBehavior.enum\" array")
      return
    }
    #expect(choices.map(\.stringValue) == QuitBehavior.allCases.map(\.rawValue))
    #expect(
      schema["properties"]?["quitBehavior"]?["default"]?.stringValue
        == Settings.defaultQuitBehavior.rawValue)
  }

  @Test func modeAfterPlanListsTheChoicesTheParserKnows() throws {
    let schema = try Self.loadSchema()
    guard case .array(let choices)? = schema["properties"]?["modeAfterPlan"]?["enum"] else {
      Issue.record("schema has no \"properties.modeAfterPlan.enum\" array")
      return
    }
    #expect(choices.map(\.stringValue) == PlanApprovalMode.allCases.map(\.rawValue))
    #expect(
      schema["properties"]?["modeAfterPlan"]?["default"]?.stringValue
        == Settings.defaultModeAfterPlan.rawValue)
  }

  @Test func panelSoundListsNoneAndTheSystemSounds() throws {
    let schema = try Self.loadSchema()
    guard case .array(let choices)? = schema["properties"]?["panelSound"]?["enum"] else {
      Issue.record("schema has no \"properties.panelSound.enum\" array")
      return
    }
    #expect(choices.map(\.stringValue) == PanelSound.choices(installed: PanelSound.systemNames))
    #expect(
      schema["properties"]?["panelSound"]?["default"]?.stringValue == Settings.defaultPanelSound)
  }

  @Test func appearanceAndAccentColorMatchWhatTheParserKnows() throws {
    let schema = try Self.loadSchema()
    guard case .array(let choices)? = schema["properties"]?["appearance"]?["enum"] else {
      Issue.record("schema has no \"properties.appearance.enum\" array")
      return
    }
    #expect(choices.map(\.stringValue) == AppearanceChoice.allCases.map(\.rawValue))
    #expect(
      schema["properties"]?["appearance"]?["default"]?.stringValue
        == Settings.defaultAppearance.rawValue)
    #expect(
      schema["properties"]?["accentColor"]?["default"]?.stringValue
        == Settings.defaultAccentColor.hex)
  }

  @Test func waitingNoticeKeysMatchWhatTheParserKnows() throws {
    let schema = try Self.loadSchema()
    #expect(schema["properties"]?["waitingNotices"]?["type"]?.stringValue == "boolean")
    #expect(schema["properties"]?["waitingNotices"]?["default"]?.boolValue == true)
    #expect(
      schema["properties"]?["waitingNoticeDelay"]?["default"]
        == .int(Int64(Settings.defaultWaitingNoticeDelay)))
    #expect(
      Self.alternatives(schema["properties"]?["waitingNoticeDelay"]).last?["$ref"]?.stringValue
        == "#/$defs/durationText")
    #expect(
      schema["properties"]?["waitingNoticeDuration"]?["default"]
        == .int(Int64(Settings.defaultWaitingNoticeDuration)))
    #expect(
      Self.alternatives(schema["properties"]?["waitingNoticeDuration"]).last?["$ref"]?.stringValue
        == "#/$defs/durationText")
  }

  private static func alternatives(_ value: JSONValue?) -> [JSONValue] {
    value?["anyOf"]?.arrayValue ?? []
  }

  @Test func timeKeysAcceptANumberOrADurationString() throws {
    let schema = try Self.loadSchema()
    for key in ["armDelay", "chainedArmDelay", "idleSeconds", "graceSeconds"] {
      let topLevel = Self.alternatives(schema["properties"]?[key])
      #expect(topLevel.first?["type"]?.stringValue == "number")
      #expect(topLevel.last?["$ref"]?.stringValue == "#/$defs/durationText")
      let host = Self.alternatives(schema["$defs"]?["hostOverrides"]?["properties"]?[key])
      #expect(host.last?["$ref"]?.stringValue == "#/$defs/durationText")
    }
    #expect(
      Self.alternatives(schema["properties"]?["snoozeMinutes"]?["items"]).last?["$ref"]?
        .stringValue == "#/$defs/durationText")
  }

  private static func regexMatches(_ regex: NSRegularExpression, _ text: String) -> Bool {
    regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  private static func compiledPattern(_ pattern: String?) throws -> NSRegularExpression {
    let source = try #require(pattern)
    return try NSRegularExpression(pattern: source)
  }

  @Test func quietHoursPatternMatchesExactlyWhatTheParserAccepts() throws {
    let schema = try Self.loadSchema()
    let properties = schema["properties"]?["quietHours"]?["items"]?["properties"]
    let samples = [
      "9", "09", "930", "0930", "9:30", "09:30", " 9:30 ", "\t9:30", "23:59", "24:00", "0", "00:00",
      "9:3", "12:", ":30", "1960", "2400", "960", "12345", "1:2:3", "9:60", "abc", "", " ", "9 30",
      "٩:٣٠",
    ]
    for key in ["from", "to"] {
      let regex = try Self.compiledPattern(properties?[key]?["pattern"]?.stringValue)
      for sample in samples {
        #expect(
          Self.regexMatches(regex, sample) == (QuietWindow.minute(from: sample) != nil),
          "\(key) pattern disagrees with the parser on \"\(sample)\"")
      }
    }
  }

  @Test func durationPatternMatchesExactlyWhatTheParserAccepts() throws {
    let schema = try Self.loadSchema()
    let regex = try Self.compiledPattern(schema["$defs"]?["durationText"]?["pattern"]?.stringValue)
    let samples = [
      "90s", "15m", "1h", "250ms", "1.5h", "5", "5.5", ".5", "5.", "15M", "15MS", "2H", "15 m",
      " 15m ", "15m ", "m", "ms", "-5m", "+5m", "1e3s", "1E3", "0", "0s", "1.2.3s", "5x", "", " ",
      "1,5s",
    ]
    for sample in samples {
      #expect(
        Self.regexMatches(regex, sample) == (DurationText.parse(sample, bareUnit: 60) != nil),
        "duration pattern disagrees with the parser on \"\(sample)\"")
    }
  }

  @Test func topLevelAndHostBlocksForbidAdditionalProperties() throws {
    let schema = try Self.loadSchema()
    #expect(schema["additionalProperties"]?.boolValue == false)
    guard case .object(let hosts)? = schema["properties"]?["hosts"] else {
      Issue.record("schema has no \"properties.hosts\" object")
      return
    }
    #expect(hosts["additionalProperties"]?.boolValue == false)
    #expect(schema["$defs"]?["hostOverrides"]?["additionalProperties"]?.boolValue == false)
  }
}
