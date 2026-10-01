import Foundation
import Testing

@testable import ApprovalCore

private func parse(_ json: String) -> (file: ConfigFile, logLines: [String]) {
  ConfigFileParser.parse(Data(json.utf8))
}

private func edited(_ text: String, _ edits: PreferenceEdit...) throws -> JSONValue {
  let bytes = try ConfigEdit.applying(edits, to: Array(text.utf8))
  return try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
}

private func withoutSchema(_ value: JSONValue) -> JSONValue {
  guard case .object(var object) = value else { return value }
  object["$schema"] = nil
  return .object(object)
}

@Suite struct AgentSettingsConfigTests {
  @Test func approvalCardDelayAcceptsUnitStrings() {
    let (file, logLines) = parse(#"{ "approvalCardDelay": "1.5s" }"#)
    #expect(logLines.isEmpty)
    #expect(file.approvalCardDelay == 1.5)
  }

  @Test func approvalCardDelayOutOfRangeLogsTheDurationLine() {
    let (file, logLines) = parse(#"{ "approvalCardDelay": "20m" }"#)
    #expect(file.approvalCardDelay == nil)
    #expect(
      logLines == ["approvalCardDelay: expected a duration from 1s to 10m, using default 5s"])
  }

  @Test func waitingNoticeDelayCanBeSetPerAgent() {
    let (file, logLines) = parse(
      #"{ "waitingNoticeMinutes": 5, "hosts": { "codex": { "waitingNoticeMinutes": "90s" } } }"#)
    #expect(logLines.isEmpty)
    #expect(Settings.resolve(file: file, host: .codex).waitingNoticeDelay == 90)
    #expect(Settings.resolve(file: file, host: .cursor).waitingNoticeDelay == 300)
  }
}

@Suite struct AgentSettingsEditTests {
  @Test func forAgentCreatesTheHostsObjectAndTheAgent() throws {
    let result = try edited("{}", .forAgent(.cursor, .armDelay(0.25)))
    #expect(
      withoutSchema(result)
        == .object(["hosts": .object(["cursor": .object(["armDelay": .double(0.25)])])]))
  }

  @Test func forAgentKeepsTheAgentsOtherKeys() throws {
    let result = try edited(
      #"{ "hosts": { "cursor": { "idleSeconds": 7 } } }"#, .forAgent(.cursor, .armDelay(0.25)))
    #expect(
      result
        == .object([
          "hosts": .object(["cursor": .object(["idleSeconds": .int(7), "armDelay": .double(0.25)])])
        ]))
  }

  @Test func forAgentResetRemovesOnlyThatKey() throws {
    let result = try edited(
      #"{ "hosts": { "codex": { "idleSeconds": 7, "armDelay": 1 } } }"#,
      .forAgent(.codex, .reset(.idleSeconds)))
    #expect(result == .object(["hosts": .object(["codex": .object(["armDelay": .int(1)])])]))
  }

  @Test func forAgentIgnoresEditsOutsideTheAllowedList() throws {
    let original = #"{ "armDelay": 1 }"#
    let bytes = try ConfigEdit.applying(
      [.forAgent(.claude, .quietHours([])), .forAgent(.claude, .reset(.quietHours))],
      to: Array(original.utf8))
    #expect(String(decoding: bytes, as: UTF8.self) == original)
  }

  @Test func forAgentWritesTheApprovalCardBool() throws {
    let result = try edited("{}", .forAgent(.claude, .approvalCard(true)))
    #expect(
      withoutSchema(result)
        == .object(["hosts": .object(["claude": .object(["approvalCard": .bool(true)])])]))
  }

  @Test func forAgentKeyIsTheInnerKey() {
    #expect(PreferenceEdit.forAgent(.codex, .waitingNoticeDelay(90)).key == .waitingNoticeMinutes)
  }

  @Test func resettingTheApprovalCardRemovesTheTopLevelAndAgentValues() throws {
    let result = try edited(
      #"""
      { "approvalCard": false, "hosts": {
        "codex": { "approvalCard": true }, "cursor": { "approvalCard": false, "armDelay": 1 } } }
      """#,
      .reset(.approvalCard))
    #expect(
      result
        == .object([
          "hosts": .object([
            "codex": .object([:]), "cursor": .object(["armDelay": .int(1)]),
          ])
        ]))
  }

  @Test func writesTheApprovalCardAndItsDelayAtTheTopLevel() throws {
    let result = try edited("{}", .approvalCard(false), .approvalCardDelay(2.5))
    #expect(
      withoutSchema(result)
        == .object(["approvalCard": .bool(false), "approvalCardDelay": .double(2.5)]))
  }

  @Test func removingAgentDelaysResetsOnlyTheDelayKeys() {
    let (file, _) = parse(
      #"""
      { "hosts": { "codex": { "idleSeconds": 7 },
        "cursor": { "armDelay": 1, "approvalCard": true } } }
      """#)
    #expect(
      PreferenceEdit.removingAgentDelays(in: file) == [
        .forAgent(.codex, .reset(.idleSeconds)), .forAgent(.cursor, .reset(.armDelay)),
      ])
  }
}

@Suite struct AgentSettingsValuesTests {
  @Test func approvalCardAgentsDefaultToTheThreeAgents() {
    #expect(
      PreferenceValues(file: ConfigFile()).approvalCardAgents == [.codex, .cursor, .antigravity])
  }

  @Test func approvalCardAgentsFollowTheTopLevelAndAgentValues() {
    let (file, _) = parse(
      #"{ "approvalCard": false, "hosts": { "cursor": { "approvalCard": true } } }"#)
    #expect(PreferenceValues(file: file).approvalCardAgents == [.cursor])
  }

  @Test func resetsTheNewNamesToTheirDefaults() {
    let changed = PreferenceValues(approvalCardDelay: 30, approvalCardAgents: [])
    #expect(
      changed.applying(.reset(.approvalCard)).approvalCardAgents == [.codex, .cursor, .antigravity])
    #expect(changed.applying(.reset(.approvalCardDelay)).approvalCardDelay == 5)
  }

  @Test func resetLinesNameTheOldAndTheDefaultValue() {
    let current = PreferenceValues(approvalCardDelay: 10, approvalCardAgents: [.codex, .cursor])
    #expect(
      PreferenceReset.line(for: .approvalCard, current: current)
        == "Approval card: Codex and Cursor → Codex, Cursor and Antigravity")
    #expect(
      PreferenceReset.line(
        for: .approvalCard, current: PreferenceValues(approvalCardAgents: []))
        == "Approval card: No agents → Codex, Cursor and Antigravity")
    #expect(
      PreferenceReset.line(for: .approvalCardDelay, current: current)
        == "Show card after: 10 s → 5 s")
  }

  @Test func detectsAChangedApprovalCardAndDelay() {
    let (file, _) = parse(#"{ "hosts": { "claude": { "approvalCard": true } } }"#)
    #expect(PreferenceReset.isChanged(.approvalCard, in: file))
    #expect(!PreferenceReset.isChanged(.approvalCard, in: ConfigFile()))
    #expect(PreferenceReset.isChanged(.approvalCardDelay, in: ConfigFile(approvalCardDelay: 9)))
    #expect(!PreferenceReset.isChanged(.approvalCardDelay, in: ConfigFile(approvalCardDelay: 5)))
  }

  @Test func namesTheNewValuesInAnAgentsOverrides() {
    let overrides = ConfigFile.HostOverrides(
      waitingNoticeDelay: 120, approvalCard: false, approvalCardDelay: 2)
    #expect(
      PreferenceOverrides.values(in: overrides) == [
        "notice after 2 minutes", "approval card off", "show card after 2 s",
      ])
  }

  @Test func listsTheAgentsWithTheirOwnDelays() {
    let (file, _) = parse(
      #"""
      { "hosts": { "claude": { "approvalCard": true }, "codex": { "waitingNoticeMinutes": 1 },
        "antigravity": { "graceSeconds": 2 } } }
      """#)
    #expect(PreferenceOverrides.agentsWithOwnDelays(in: file) == [.codex, .antigravity])
  }

  @Test func textsTheNewNames() {
    #expect(PreferenceName.approvalCard.title == "Approval card")
    #expect(PreferenceName.approvalCardDelay.title == "Show card after")
    #expect(PreferenceName.approvalCard.defaultText == "Codex, Cursor and Antigravity")
    #expect(PreferenceName.approvalCardDelay.defaultText == "5 seconds")
  }
}
