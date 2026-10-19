import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointConfigTests {
  private func parse(_ json: String) -> (file: ConfigFile, logLines: [String]) {
    ConfigFileParser.parse(Data(json.utf8))
  }

  @Test func absentKeyResolvesToTheEnabledDefaultForClaudeAndCodex() {
    let (file, logLines) = parse("{}")
    #expect(logLines.isEmpty)
    #expect(file.contextCheckpoints == nil)
    #expect(file.contextCheckpointsClaude == nil)
    let settings = Settings.resolve(file: file, host: .claude)
    #expect(settings.contextCheckpoints == .default)
    #expect(settings.contextCheckpoints.enabled == true)
    #expect(Settings.resolve(file: file, host: .codex).contextCheckpoints.enabled == true)
    for host in [Host.cursor, .antigravity] {
      #expect(Settings.resolve(file: file, host: host).contextCheckpoints.enabled == false)
    }
  }

  @Test func explicitFalseKeepsClaudeOff() {
    let (file, _) = parse(#"{"contextCheckpoints": {"enabled": false}}"#)
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.enabled == false)
  }

  @Test func nonBooleanEnabledLogsTheEnabledDefault() {
    let (file, logLines) = parse(#"{"contextCheckpoints": {"enabled": "yes"}}"#)
    #expect(logLines == ["contextCheckpoints.enabled: not a boolean, using default true"])
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.enabled == true)
  }

  @Test func fullBlockParsesEveryValueAndHostBlockOverrides() {
    let (file, logLines) = parse(
      """
      {
        "contextCheckpoints": {
          "enabled": true,
          "mode": "panel",
          "thresholds": { "200k": [1000, 2000, 3000, 4000], "1m": [10, 20, 30, 40] },
          "modelThresholds": { "claude-opus-5-5[1m]": [250000, 350000, 450000, 650000] },
          "rearmBelow": 0.5,
          "handoffFile": "docs/handoff.md",
          "notes": {
            "soft": "top soft",
            "status": "top status",
            "insist": "top insist",
            "stop": "top stop",
            "compact": "top compact",
            "handoff": "top handoff"
          },
          "menuBarMeter": true,
          "coldCacheCard": false,
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
    #expect(top?.standardThresholds == [1000, 2000, 3000, 4000])
    #expect(top?.millionThresholds == [10, 20, 30, 40])
    #expect(top?.modelThresholds == ["claude-opus-5-5[1m]": [250_000, 350_000, 450_000, 650_000]])
    #expect(top?.rearmBelow == 0.5)
    #expect(top?.handoffFile == "docs/handoff.md")
    #expect(top?.menuBarMeter == true)
    #expect(top?.coldCacheCard == false)
    #expect(top?.notes.count == 6)

    let resolved = Settings.resolve(file: file, host: .claude).contextCheckpoints
    #expect(resolved.enabled)
    #expect(resolved.mode == .silent)
    #expect(resolved.notes.soft == "host soft")
    #expect(resolved.notes.status == "top status")
    #expect(resolved.notes.insist == "top insist")
    #expect(resolved.notes.stop == "top stop")
    #expect(resolved.notes.compact == "top compact")
    #expect(resolved.notes.handoff == "top handoff")
    #expect(resolved.rearmBelow == 0.5)
    #expect(resolved.handoffFile == "docs/handoff.md")
    #expect(resolved.menuBarMeter)
    #expect(!resolved.coldCacheCard)
  }

  @Test func threeValueLaddersStillParse() {
    let (file, logLines) = parse(
      #"{"contextCheckpoints": {"thresholds": {"200k": [1, 2, 3]}}}"#)
    #expect(logLines.isEmpty)
    #expect(file.contextCheckpoints?.standardThresholds == [1, 2, 3])
  }

  @Test func twoValueLadderParsesAndOneOrFiveAreRejected() {
    let (two, twoLog) = parse(#"{"contextCheckpoints": {"thresholds": {"200k": [100, 200]}}}"#)
    #expect(twoLog.isEmpty)
    #expect(two.contextCheckpoints?.standardThresholds == [100, 200])
    let (one, oneLog) = parse(#"{"contextCheckpoints": {"thresholds": {"200k": [100]}}}"#)
    #expect(one.contextCheckpoints?.standardThresholds == nil)
    #expect(
      oneLog == [
        "contextCheckpoints.thresholds.200k: expected 2 to 4 ascending whole numbers of tokens, using default [100000, 130000, 160000]"
      ])
    let (five, fiveLog) = parse(
      #"{"contextCheckpoints": {"thresholds": {"1m": [1, 2, 3, 4, 5]}}}"#)
    #expect(five.contextCheckpoints?.millionThresholds == nil)
    #expect(
      fiveLog == [
        "contextCheckpoints.thresholds.1m: expected 2 to 4 ascending whole numbers of tokens, using default [200000, 300000, 500000]"
      ])
  }

  @Test func hostStopNoteBeatsTheTopOne() {
    let (file, _) = parse(
      #"{"contextCheckpoints": {"notes": {"stop": "top"}, "hosts": {"claude": {"notes": {"stop": "host"}}}}}"#
    )
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.notes.stop == "host")
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
          "modelThresholds": { "good": [1, 2, 3], "bad": [1], "long": [1, 2, 3, 4, 5] },
          "rearmBelow": 2,
          "handoffFile": "",
          "notes": { "soft": "\(longNote)", "status": "kept" }
        }
      }
      """)
    #expect(
      logLines == [
        "contextCheckpoints.mode: expected \"panel\" or \"silent\", using default \"panel\"",
        "contextCheckpoints.thresholds.200k: expected 2 to 4 ascending whole numbers of tokens, using default [100000, 130000, 160000]",
        "contextCheckpoints.modelThresholds.bad: expected 2 to 4 ascending whole numbers of tokens, ignored",
        "contextCheckpoints.modelThresholds.long: expected 2 to 4 ascending whole numbers of tokens, ignored",
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
        "contextCheckpoints.thresholds.1m: expected 2 to 4 ascending whole numbers of tokens, using default [200000, 300000, 500000]"
      ])
  }

  @Test func unknownKeysAndUnsupportedHostsAreLogged() {
    let (file, logLines) = parse(
      """
      {
        "contextCheckpoints": {
          "foo": 1,
          "enabled": true,
          "hosts": { "cursor": { "enabled": true }, "claude": { "hosts": {}, "bar": 2 } }
        }
      }
      """)
    #expect(logLines.contains("unknown key \"contextCheckpoints.foo\", ignored"))
    #expect(
      logLines.contains(
        "contextCheckpoints.hosts.cursor: context checkpoints support only Claude Code and Codex, ignored"
      ))
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

  @Test func cursorAndAntigravityNeverEnableCheckpoints() {
    let (file, _) = parse(
      #"{"contextCheckpoints": {"enabled": true, "hosts": {"claude": {"enabled": true}}}}"#)
    for host in [Host.cursor, .antigravity] {
      let settings = Settings.resolve(file: file, host: host).contextCheckpoints
      #expect(settings.enabled == false)
      #expect(settings == .off)
    }
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.enabled)
  }

  @Test func codexIsEnabledByDefaultAndTheTopSwitchTurnsItOff() {
    let (defaults, _) = parse("{}")
    #expect(Settings.resolve(file: defaults, host: .codex).contextCheckpoints.enabled)
    let (off, _) = parse(#"{"contextCheckpoints": {"enabled": false}}"#)
    #expect(Settings.resolve(file: off, host: .codex).contextCheckpoints.enabled == false)
  }

  @Test func codexHostSwitchWinsOverTheTopSwitch() {
    let (file, logLines) = parse(
      #"{"contextCheckpoints": {"enabled": true, "hosts": {"codex": {"enabled": false}}}}"#)
    #expect(logLines.isEmpty)
    #expect(Settings.resolve(file: file, host: .codex).contextCheckpoints.enabled == false)
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.enabled)
  }

  @Test func codexIsSilentWhateverTheTopModeSays() {
    let (file, _) = parse(#"{"contextCheckpoints": {"mode": "panel"}}"#)
    let settings = Settings.resolve(file: file, host: .codex).contextCheckpoints
    #expect(settings.mode == .silent)
    #expect(settings.menuBarMeter == false)
    #expect(settings.coldCacheCard == false)
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.mode == .panel)
  }

  @Test func codexNoteWinsOverTheTopNote() {
    let (file, _) = parse(
      """
      {"contextCheckpoints": {"notes": {"soft": "top soft", "stop": "top stop"},
        "hosts": {"codex": {"notes": {"soft": "codex soft"}}}}}
      """)
    let notes = Settings.resolve(file: file, host: .codex).contextCheckpoints.notes
    #expect(notes.soft == "codex soft")
    #expect(notes.stop == "top stop")
  }

  @Test func codexReadsTheBlockWithoutALogLine() {
    let (file, logLines) = parse(
      #"{"contextCheckpoints": {"hosts": {"codex": {"enabled": false, "rearmBelow": 0.5}}}}"#)
    #expect(logLines.isEmpty)
    #expect(file.contextCheckpointsCodex?.enabled == false)
    #expect(file.contextCheckpointsCodex?.rearmBelow == 0.5)
  }

  @Test func codexLogsAndDropsTheClaudeOnlyKeys() {
    let (file, logLines) = parse(
      #"{"contextCheckpoints": {"hosts": {"codex": {"thresholds": {"200k": [1, 2, 3, 4]}}}}}"#)
    #expect(logLines == ["contextCheckpoints.hosts.codex.thresholds: Claude Code only, ignored"])
    #expect(file.contextCheckpointsCodex?.standardThresholds == nil)
  }

  @Test func tokenTextRoundsToThousandsThenMillions() {
    #expect(ContextCheckpointNotes.tokenText(212_345) == "212K")
    #expect(ContextCheckpointNotes.tokenText(999_499) == "999K")
    #expect(ContextCheckpointNotes.tokenText(999_500) == "1.0M")
    #expect(ContextCheckpointNotes.tokenText(1_250_000) == "1.3M")
  }

  @Test func renderReplacesEveryPlaceholder() {
    let text = ContextCheckpointNotes.render(
      "{tokens} and {tokens}: write {handoffFile}, then read {handoffFile}, {compactions} times",
      tokens: 212_345, handoffFile: "notes/h.md", compactions: 7)
    #expect(text == "212K and 212K: write notes/h.md, then read notes/h.md, 7 times")
  }

  @Test func theLimitNoteIsTheSeventhNoteAndUsesTheCompactionCount() {
    #expect(ContextCheckpointNotes.names.last == "limit")
    #expect(ContextCheckpointNotes.names.count == 7)
    #expect(
      ContextCheckpointNotes.default.text(named: "limit") == ContextCheckpointNotes.default.limit)
    #expect(ContextCheckpointNotes.default.limit.contains("{compactions}"))
  }

  @Test func theDefaultStopNoteKeepsStateAndNamesTheHandoffFile() {
    let text = ContextCheckpointNotes.render(
      ContextCheckpointNotes.default.stop, tokens: 165_000, handoffFile: "notes/h.md",
      compactions: 0)
    #expect(text.contains("clean nothing up"))
    #expect(text.contains("notes/h.md"))
    #expect(!text.contains("{handoffFile}"))
  }

  @Test func maxCompactionsAndChoicesParse() {
    let (file, logLines) = parse(
      """
      {
        "contextCheckpoints": {
          "maxCompactions": 3,
          "choices": {
            "soft": ["handoff", "continue"],
            "status": ["compact", "handoff", "continue", "mute"]
          },
          "hosts": { "claude": { "choices": { "status": ["continue"] } } }
        }
      }
      """)
    #expect(logLines.isEmpty)
    #expect(file.contextCheckpoints?.maxCompactions == 3)
    #expect(file.contextCheckpoints?.choices["soft"] == [.handOff, .continueWorking])
    #expect(
      file.contextCheckpoints?.choices["status"] == [
        .compactAfterStep, .handOff, .continueWorking, .notThisSession,
      ])

    let resolved = Settings.resolve(file: file, host: .claude).contextCheckpoints
    #expect(resolved.maxCompactions == 3)
    #expect(resolved.choices.soft == [.handOff, .continueWorking])
    #expect(resolved.choices.status == [.continueWorking])
    #expect(resolved.choices.insist == ContextCheckpointChoices.default.insist)
  }

  @Test func absentValuesResolveToTheDefaults() {
    let (file, _) = parse(#"{"contextCheckpoints": {}}"#)
    let resolved = Settings.resolve(file: file, host: .claude).contextCheckpoints
    #expect(resolved.maxCompactions == 5)
    #expect(resolved.choices == .default)
  }

  @Test(arguments: ["-1", "51", "2.5", "\"3\"", "true"])
  func aBadMaxCompactionsLogsAndKeepsTheDefault(value: String) {
    let (file, logLines) = parse(#"{"contextCheckpoints": {"maxCompactions": \#(value)}}"#)
    #expect(
      logLines == [
        "contextCheckpoints.maxCompactions: expected a whole number from 0 to 50, using default 5"
      ])
    #expect(file.contextCheckpoints?.maxCompactions == nil)
    #expect(Settings.resolve(file: file, host: .claude).contextCheckpoints.maxCompactions == 5)
  }

  @Test(arguments: [0, 50])
  func theMaxCompactionsBoundsAreAccepted(value: Int) {
    let (file, logLines) = parse(#"{"contextCheckpoints": {"maxCompactions": \#(value)}}"#)
    #expect(logLines.isEmpty)
    #expect(file.contextCheckpoints?.maxCompactions == value)
  }

  @Test(arguments: [
    #"["continue", "continue"]"#,
    #"["later"]"#,
    "[]",
    #"["compact", "handoff", "continue", "mute", "compact"]"#,
    #""compact""#,
  ])
  func aBadChoiceListLogsAndKeepsTheDefault(list: String) {
    let (file, logLines) = parse(
      #"{"contextCheckpoints": {"choices": {"soft": \#(list), "status": ["mute"]}}}"#)
    #expect(
      logLines == [
        "contextCheckpoints.choices.soft: expected 1 to 4 different choices from compact, handoff, continue and mute, using the default"
      ])
    #expect(file.contextCheckpoints?.choices["soft"] == nil)
    #expect(file.contextCheckpoints?.choices["status"] == [.notThisSession])
    let resolved = Settings.resolve(file: file, host: .claude).contextCheckpoints
    #expect(resolved.choices.soft == ContextCheckpointChoices.default.soft)
  }

  @Test func anUnknownChoicesKeyIsLoggedAndIgnored() {
    let (file, logLines) = parse(
      #"{"contextCheckpoints": {"choices": {"stop": ["mute"], "soft": ["mute"]}}}"#)
    #expect(logLines == ["unknown key \"contextCheckpoints.choices.stop\", ignored"])
    #expect(file.contextCheckpoints?.choices == ["soft": [.notThisSession]])
  }

  @Test func choicesThatAreNotAnObjectAreIgnored() {
    let (file, logLines) = parse(#"{"contextCheckpoints": {"choices": ["mute"]}}"#)
    #expect(logLines == ["contextCheckpoints.choices: expected an object, ignored"])
    #expect(file.contextCheckpoints?.choices.isEmpty == true)
  }

  @Test func codexLogsAndDropsMaxCompactionsAndChoicesAndKeepsTheDefaults() {
    let (file, logLines) = parse(
      """
      {"contextCheckpoints": {"hosts": {"codex": {
        "maxCompactions": 1, "choices": {"soft": ["mute"]}
      }}}}
      """)
    #expect(
      logLines == [
        "contextCheckpoints.hosts.codex.maxCompactions: Claude Code only, ignored",
        "contextCheckpoints.hosts.codex.choices: Claude Code only, ignored",
      ])
    #expect(file.contextCheckpointsCodex?.maxCompactions == nil)
    #expect(file.contextCheckpointsCodex?.choices.isEmpty == true)
    let resolved = Settings.resolve(file: file, host: .codex).contextCheckpoints
    #expect(resolved.maxCompactions == 5)
    #expect(resolved.choices == .default)
  }

  @Test func codexIgnoresTheTopLevelMaxCompactionsAndChoices() {
    let (file, _) = parse(
      #"{"contextCheckpoints": {"maxCompactions": 1, "choices": {"soft": ["mute"]}}}"#)
    let resolved = Settings.resolve(file: file, host: .codex).contextCheckpoints
    #expect(resolved.maxCompactions == 5)
    #expect(resolved.choices == .default)
  }
}
