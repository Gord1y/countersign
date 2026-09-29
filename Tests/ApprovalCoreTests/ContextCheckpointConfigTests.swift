import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointConfigTests {
  private func parse(_ json: String) -> (file: ConfigFile, logLines: [String]) {
    ConfigFileParser.parse(Data(json.utf8))
  }

  @Test func absentKeyResolvesToTheDisabledDefault() {
    let (file, logLines) = parse("{}")
    #expect(logLines.isEmpty)
    #expect(file.contextCheckpoints == nil)
    #expect(file.contextCheckpointsClaude == nil)
    let settings = Settings.resolve(file: file, host: .claude)
    #expect(settings.contextCheckpoints == .default)
    #expect(settings.contextCheckpoints.enabled == false)
  }

  @Test func fullBlockParsesEveryValueAndHostBlockOverrides() {
    let (file, logLines) = parse(
      """
      {
        "contextCheckpoints": {
          "enabled": true,
          "mode": "panel",
          "thresholds": { "200k": [1000, 2000, 3000], "1m": [10, 20, 30] },
          "modelThresholds": { "claude-opus-5-5[1m]": [250000, 350000, 450000] },
          "rearmBelow": 0.5,
          "handoffFile": "docs/handoff.md",
          "notes": {
            "soft": "top soft",
            "status": "top status",
            "insist": "top insist",
            "compact": "top compact",
            "handoff": "top handoff"
          },
          "menuBarMeter": true,
          "hosts": {
            "claude": { "mode": "silent", "notes": { "soft": "host soft" } }
          }
        }
      }
      """)
    #expect(logLines.isEmpty)
    let top = file.contextCheckpoints
    #expect(top?.enabled == true)
    #expect(top?.mode == .panel)
    #expect(top?.standardThresholds == [1000, 2000, 3000])
    #expect(top?.millionThresholds == [10, 20, 30])
    #expect(top?.modelThresholds == ["claude-opus-5-5[1m]": [250_000, 350_000, 450_000]])
    #expect(top?.rearmBelow == 0.5)
    #expect(top?.handoffFile == "docs/handoff.md")
    #expect(top?.menuBarMeter == true)
    #expect(top?.notes.count == 5)

    let resolved = Settings.resolve(file: file, host: .claude).contextCheckpoints
    #expect(resolved.enabled)
    #expect(resolved.mode == .silent)
    #expect(resolved.notes.soft == "host soft")
    #expect(resolved.notes.status == "top status")
    #expect(resolved.notes.insist == "top insist")
    #expect(resolved.notes.compact == "top compact")
    #expect(resolved.notes.handoff == "top handoff")
    #expect(resolved.rearmBelow == 0.5)
    #expect(resolved.handoffFile == "docs/handoff.md")
    #expect(resolved.menuBarMeter)
  }

  @Test func partialNotesKeepTheDefaultsForTheRest() {
    let (file, _) = parse(#"{"contextCheckpoints": {"notes": {"handoff": "only this"}}}"#)
    let resolved = Settings.resolve(file: file, host: .claude).contextCheckpoints
    #expect(resolved.notes.handoff == "only this")
    #expect(resolved.notes.soft == ContextCheckpointNotes.default.soft)
    #expect(resolved.notes.compact == ContextCheckpointNotes.default.compact)
  }

  @Test func eachBadValueLogsItsLineAndKeepsTheRest() {
    let longNote = String(repeating: "a", count: 5000)
    let (file, logLines) = parse(
      """
      {
        "contextCheckpoints": {
          "enabled": true,
          "mode": "x",
          "thresholds": { "200k": [3, 2, 1], "1m": [10, 20, 30] },
          "modelThresholds": { "good": [1, 2, 3], "bad": [1, 2] },
          "rearmBelow": 2,
          "handoffFile": "",
          "notes": { "soft": "\(longNote)", "status": "kept" }
        }
      }
      """)
    #expect(
      logLines == [
        "contextCheckpoints.mode: expected \"panel\" or \"silent\", using default \"panel\"",
        "contextCheckpoints.thresholds.200k: expected 3 ascending whole numbers of tokens, using default [100000, 130000, 160000]",
        "contextCheckpoints.modelThresholds.bad: expected 3 ascending whole numbers of tokens, ignored",
        "contextCheckpoints.rearmBelow: expected a number from 0.1 to 0.95, using default 0.6",
        "contextCheckpoints.handoffFile: expected a non-empty string, using default \"notes/handoff.md\"",
        "contextCheckpoints.notes.soft: expected text of 1 to 4000 characters, using the default",
      ])
    let values = file.contextCheckpoints
    #expect(values?.enabled == true)
    #expect(values?.mode == nil)
    #expect(values?.standardThresholds == nil)
    #expect(values?.millionThresholds == [10, 20, 30])
    #expect(values?.modelThresholds == ["good": [1, 2, 3]])
    #expect(values?.rearmBelow == nil)
    #expect(values?.handoffFile == nil)
    #expect(values?.notes == ["status": "kept"])
  }

  @Test func badMillionLadderNamesItsOwnDefault() {
    let (_, logLines) = parse(
      #"{"contextCheckpoints": {"thresholds": {"1m": [5, 5, 6]}}}"#)
    #expect(
      logLines == [
        "contextCheckpoints.thresholds.1m: expected 3 ascending whole numbers of tokens, using default [200000, 300000, 400000]"
      ])
  }

  @Test func unknownKeysAndUnsupportedHostsAreLogged() {
    let (file, logLines) = parse(
      """
      {
        "contextCheckpoints": {
          "foo": 1,
          "enabled": true,
          "hosts": { "codex": { "enabled": true }, "claude": { "hosts": {}, "bar": 2 } }
        }
      }
      """)
    #expect(logLines.contains("unknown key \"contextCheckpoints.foo\", ignored"))
    #expect(
      logLines.contains(
        "contextCheckpoints.hosts.codex: context checkpoints support only Claude Code, ignored"))
    #expect(logLines.contains("unknown key \"contextCheckpoints.hosts.claude.hosts\", ignored"))
    #expect(logLines.contains("unknown key \"contextCheckpoints.hosts.claude.bar\", ignored"))
    #expect(logLines.count == 4)
    #expect(file.contextCheckpoints?.enabled == true)
  }

  @Test func nonObjectBlocksAreIgnored() {
    let (topFile, topLines) = parse(#"{"contextCheckpoints": 3}"#)
    #expect(topLines == ["contextCheckpoints: expected an object, ignored"])
    #expect(topFile.contextCheckpoints == nil)

    let (hostsFile, hostsLines) = parse(#"{"contextCheckpoints": {"hosts": []}}"#)
    #expect(hostsLines == ["contextCheckpoints.hosts: expected an object, ignored"])
    #expect(hostsFile.contextCheckpointsClaude == nil)
  }

  @Test func otherHostsNeverEnableCheckpoints() {
    let (file, _) = parse(
      #"{"contextCheckpoints": {"enabled": true, "hosts": {"claude": {"enabled": true}}}}"#)
    for host in [Host.codex, .cursor, .antigravity] {
      let settings = Settings.resolve(file: file, host: host).contextCheckpoints
      #expect(settings.enabled == false)
      #expect(settings == .default)
    }
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.enabled)
  }

  @Test func tokenTextRoundsToThousandsThenMillions() {
    #expect(ContextCheckpointNotes.tokenText(212_345) == "212K")
    #expect(ContextCheckpointNotes.tokenText(999_499) == "999K")
    #expect(ContextCheckpointNotes.tokenText(999_500) == "1.0M")
    #expect(ContextCheckpointNotes.tokenText(1_250_000) == "1.3M")
  }

  @Test func renderReplacesEveryPlaceholder() {
    let text = ContextCheckpointNotes.render(
      "{tokens} and {tokens}: write {handoffFile}, then read {handoffFile}",
      tokens: 212_345, handoffFile: "notes/h.md")
    #expect(text == "212K and 212K: write notes/h.md, then read notes/h.md")
  }
}
