import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ApprovalCardConfigTests {
  private func parse(_ json: String) -> (file: ConfigFile, logLines: [String]) {
    ConfigFileParser.parse(Data(json.utf8))
  }

  @Test(arguments: [
    (ApprovalCore.Host.claude, false), (.codex, true), (.cursor, true), (.antigravity, true),
  ])
  func defaultsPerAgent(host: ApprovalCore.Host, expected: Bool) {
    let (file, logLines) = parse("{}")
    #expect(logLines.isEmpty)
    #expect(Settings.defaultApprovalCard(for: host) == expected)
    let settings = Settings.resolve(file: file, host: host)
    #expect(settings.approvalCard == expected)
    #expect(settings.approvalCardDelay == 5)
  }

  @Test func topLevelOnTurnsClaudeCodeOn() {
    let (file, logLines) = parse(#"{ "approvalCard": true }"#)
    #expect(logLines.isEmpty)
    #expect(file.approvalCard == true)
    #expect(Settings.resolve(file: file, host: .claude).approvalCard)
  }

  @Test func topLevelOffTurnsEveryAgentOff() {
    let (file, _) = parse(#"{ "approvalCard": false }"#)
    for host in ApprovalCore.Host.allCases {
      #expect(Settings.resolve(file: file, host: host).approvalCard == false)
    }
  }

  @Test func hostOverrideTurnsCursorOffAndLeavesTheOthers() {
    let (file, logLines) = parse(#"{ "hosts": { "cursor": { "approvalCard": false } } }"#)
    #expect(logLines.isEmpty)
    #expect(file.cursor?.approvalCard == false)
    #expect(Settings.resolve(file: file, host: .cursor).approvalCard == false)
    #expect(Settings.resolve(file: file, host: .codex).approvalCard)
    #expect(Settings.resolve(file: file, host: .antigravity).approvalCard)
    #expect(Settings.resolve(file: file, host: .claude).approvalCard == false)
  }

  @Test func hostOverrideWinsOverTopLevel() {
    let (file, _) = parse(
      #"{ "approvalCard": true, "hosts": { "claude": { "approvalCard": false } } }"#)
    #expect(Settings.resolve(file: file, host: .claude).approvalCard == false)
    #expect(Settings.resolve(file: file, host: .codex).approvalCard)
  }

  @Test func approvalCardWrongTypeFallsBackToTheAgentDefault() {
    let (file, logLines) = parse(
      #"{ "approvalCard": "yes", "hosts": { "codex": { "approvalCard": 1 } } }"#)
    #expect(file.approvalCard == nil)
    #expect(file.codex?.approvalCard == nil)
    #expect(
      logLines.sorted() == [
        "approvalCard: not a boolean, using the agent's default",
        "hosts.codex.approvalCard: not a boolean, using the agent's default",
      ])
    #expect(Settings.resolve(file: file, host: .codex).approvalCard)
  }

  @Test func readsValidDelays() {
    for (text, seconds) in [("1", 1.0), ("2.5", 2.5), ("30", 30.0), ("600", 600.0)] {
      let (file, logLines) = parse(#"{ "approvalCardDelay": \#(text) }"#)
      #expect(logLines.isEmpty)
      #expect(file.approvalCardDelay == seconds)
      #expect(Settings.resolve(file: file, host: .cursor).approvalCardDelay == seconds)
    }
  }

  @Test func hostDelayWinsOverTopLevel() {
    let (file, logLines) = parse(
      #"{ "approvalCardDelay": 20, "hosts": { "cursor": { "approvalCardDelay": 3 } } }"#)
    #expect(logLines.isEmpty)
    #expect(Settings.resolve(file: file, host: .cursor).approvalCardDelay == 3)
    #expect(Settings.resolve(file: file, host: .codex).approvalCardDelay == 20)
  }

  @Test func delayOutOfRangeOrWrongTypeFallsBackToTheDefaultWithOneLine() {
    for bad in ["0", "0.5", "601", "-3", "\"20m\"", "\"soon\"", "true", "null"] {
      let (file, logLines) = parse(#"{ "approvalCardDelay": \#(bad) }"#)
      #expect(file.approvalCardDelay == nil)
      #expect(
        logLines == [
          "approvalCardDelay: expected a duration from 1s to 10m, using default 5s"
        ])
      #expect(Settings.resolve(file: file, host: .codex).approvalCardDelay == 5)
    }
  }

  @Test func hostDelayOutOfRangeLogsItsPath() {
    let (file, logLines) = parse(#"{ "hosts": { "antigravity": { "approvalCardDelay": 900 } } }"#)
    #expect(file.antigravity?.approvalCardDelay == nil)
    #expect(
      logLines == [
        "hosts.antigravity.approvalCardDelay: expected a duration from 1s to 10m,"
          + " using default 5s"
      ])
  }
}
