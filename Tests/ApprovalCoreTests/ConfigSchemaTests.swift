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
    #expect(schema["properties"]?["waitingNotices"]?["default"]?.boolValue == false)
    #expect(schema["properties"]?["waitingNoticeMinutes"]?["type"]?.stringValue == "integer")
    #expect(
      schema["properties"]?["waitingNoticeMinutes"]?["minimum"]
        == .int(Int64(Settings.waitingNoticeMinutesRange.lowerBound)))
    #expect(
      schema["properties"]?["waitingNoticeMinutes"]?["maximum"]
        == .int(Int64(Settings.waitingNoticeMinutesRange.upperBound)))
    #expect(
      schema["properties"]?["waitingNoticeMinutes"]?["default"]
        == .int(Int64(Settings.defaultWaitingNoticeMinutes)))
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
