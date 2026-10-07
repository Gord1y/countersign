import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ConfigFileTests {
  private func parse(_ json: String) -> (file: ConfigFile, logLines: [String]) {
    ConfigFileParser.parse(Data(json.utf8))
  }

  @Test func emptyObjectYieldsAllDefaults() {
    let (file, logLines) = parse("{}")
    #expect(file == ConfigFile())
    #expect(logLines.isEmpty)
  }

  @Test func parsesEveryTopLevelKey() {
    let (file, logLines) = parse(
      """
      {
        "armDelay": 1.5,
        "chainedArmDelay": 0.3,
        "idleSeconds": 10,
        "graceSeconds": 2,
        "handoffApps": ["com.apple.Terminal"],
        "snoozeMinutes": [2, 4, 6],
        "checkForUpdates": true,
        "quitBehavior": "pause",
        "modeAfterPlan": "acceptEdits",
        "includeHeadlessSessions": true,
        "questionNotes": true,
        "appearance": "dark",
        "accentColor": "#5B9CF6",
        "editorApp": "com.microsoft.VSCode"
      }
      """)
    #expect(logLines.isEmpty)
    #expect(file.appearance == .dark)
    #expect(file.accentColor == AccentPreset.blue.color)
    #expect(file.armDelay == 1.5)
    #expect(file.chainedArmDelay == 0.3)
    #expect(file.idleSeconds == 10)
    #expect(file.graceSeconds == 2)
    #expect(file.handoffApps == ["com.apple.Terminal"])
    #expect(file.snoozePresets == [120, 240, 360])
    #expect(file.checkForUpdates == true)
    #expect(file.quitBehavior == .pause)
    #expect(file.modeAfterPlan == .acceptEdits)
    #expect(file.includeHeadlessSessions == true)
    #expect(file.questionNotes == true)
    #expect(file.editorApp == "com.microsoft.VSCode")
  }

  @Test func waitingNoticesAreOnAndTenSecondsByDefault() {
    let (file, logLines) = parse("{}")
    #expect(file.waitingNotices == nil)
    #expect(file.waitingNoticeDelay == nil)
    #expect(logLines.isEmpty)
    let settings = Settings.resolve(file: file, host: .claude)
    #expect(settings.waitingNotices == true)
    #expect(settings.waitingNoticeDelay == 10)
  }

  @Test func readsValidWaitingNoticeValuesAsSeconds() {
    for seconds in [10, 30, 90, 3600] {
      let (file, logLines) = parse(
        #"{ "waitingNotices": true, "waitingNoticeDelay": \#(seconds) }"#)
      #expect(file.waitingNotices == true)
      #expect(file.waitingNoticeDelay == TimeInterval(seconds))
      #expect(logLines.isEmpty)
      let settings = Settings.resolve(file: file, host: .codex)
      #expect(settings.waitingNotices)
      #expect(settings.waitingNoticeDelay == TimeInterval(seconds))
    }
  }

  @Test func waitingNoticeDelayOutOfRangeOrWrongTypeFallBackToTheDefaultWithOneLine() {
    for bad in ["0", "5", "3601", "-3", "\"soon\"", "\"5s\"", "\"61m\"", "true", "null"] {
      let (file, logLines) = parse(#"{ "waitingNoticeDelay": \#(bad) }"#)
      #expect(file.waitingNoticeDelay == nil)
      #expect(
        logLines == ["waitingNoticeDelay: expected a duration from 10s to 1h, using default 10s"])
    }
  }

  @Test func waitingNoticeDelayAcceptsUnits() {
    for (text, seconds) in [("\"90s\"", 90.0), ("\"2m\"", 120.0)] {
      let (file, logLines) = parse(#"{ "waitingNoticeDelay": \#(text) }"#)
      #expect(file.waitingNoticeDelay == seconds)
      #expect(logLines.isEmpty)
    }
  }

  @Test func waitingNoticeDurationDefaultsToTenSeconds() {
    let (file, logLines) = parse("{}")
    #expect(file.waitingNoticeDuration == nil)
    #expect(logLines.isEmpty)
    #expect(Settings.resolve(file: file, host: .claude).waitingNoticeDuration == 10)
  }

  @Test func waitingNoticeDurationReadsSecondsAndUnits() {
    for (text, seconds) in [("30", 30.0), ("3", 3.0), ("3600", 3600.0), ("\"1m\"", 60.0)] {
      let (file, logLines) = parse(#"{ "waitingNoticeDuration": \#(text) }"#)
      #expect(file.waitingNoticeDuration == seconds)
      #expect(logLines.isEmpty)
      #expect(Settings.resolve(file: file, host: .cursor).waitingNoticeDuration == seconds)
    }
  }

  @Test func waitingNoticeDurationOutOfRangeFallsBackToTheDefaultWithOneLine() {
    for bad in ["2", "3601", "\"soon\"", "true"] {
      let (file, logLines) = parse(#"{ "waitingNoticeDuration": \#(bad) }"#)
      #expect(file.waitingNoticeDuration == nil)
      #expect(
        logLines == ["waitingNoticeDuration: expected a duration from 3s to 1h, using default 10s"])
    }
  }

  @Test func waitingNoticeDurationIsTopLevelOnly() {
    let (file, logLines) = parse(
      #"{ "hosts": { "cursor": { "waitingNoticeDuration": 30 } } }"#)
    #expect(logLines == [#"unknown key "hosts.cursor.waitingNoticeDuration", ignored"#])
    #expect(Settings.resolve(file: file, host: .cursor).waitingNoticeDuration == 10)
  }

  @Test func theOldWaitingNoticeMinutesKeyIsIgnored() {
    let (file, _) = parse(#"{ "waitingNoticeMinutes": 5 }"#)
    #expect(file.waitingNoticeDelay == nil)
    #expect(Settings.resolve(file: file, host: .claude).waitingNoticeDelay == 10)
  }

  @Test func armDelayAcceptsUnits() {
    let (file, logLines) = parse(#"{ "armDelay": "500ms", "chainedArmDelay": "0.25s" }"#)
    #expect(file.armDelay == 0.5)
    #expect(file.chainedArmDelay == 0.25)
    #expect(logLines.isEmpty)
  }

  @Test func armDelayStringOutOfRangeClampsAndQuotesTheValueAsWritten() {
    let (file, logLines) = parse(#"{ "armDelay": "9s" }"#)
    #expect(file.armDelay == 3)
    #expect(logLines == ["armDelay: \"9s\" is out of range 0...3, clamped to 3"])
  }

  @Test func idleAndGraceSecondsAcceptUnits() {
    let (file, logLines) = parse(#"{ "idleSeconds": "2s", "graceSeconds": "500ms" }"#)
    #expect(file.idleSeconds == 2)
    #expect(file.graceSeconds == 0.5)
    #expect(logLines.isEmpty)
  }

  @Test func idleSecondsStringOutOfRangeFallsBackAndLogsTheValueAsWritten() {
    let (file, logLines) = parse(#"{ "idleSeconds": "2m" }"#)
    #expect(file.idleSeconds == nil)
    #expect(logLines == ["idleSeconds: \"2m\" is out of range 1...30, using default 5"])
  }

  @Test func snoozeMinutesAcceptUnitsAndBareMinutes() {
    let (file, logLines) = parse(#"{ "snoozeMinutes": ["30s", 5, "1h"] }"#)
    #expect(file.snoozePresets == [30, 300, 3600])
    #expect(logLines.isEmpty)
  }

  @Test func snoozeMinutesStringBelowTheRangeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "snoozeMinutes": ["5s"] }"#)
    #expect(file.snoozePresets == nil)
    #expect(
      logLines == [
        "snoozeMinutes: expected durations from 10s to 24h, using default 1m, 5m, 15m, 30m"
      ])
  }

  @Test func hostOverridesAcceptUnits() {
    let (file, logLines) = parse(
      #"{ "hosts": { "cursor": { "armDelay": "250ms", "snoozeMinutes": ["45s"] } } }"#)
    #expect(file.cursor?.armDelay == 0.25)
    #expect(file.cursor?.snoozePresets == [45])
    #expect(logLines.isEmpty)
  }

  @Test func waitingNoticesWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "waitingNotices": "yes" }"#)
    #expect(file.waitingNotices == nil)
    #expect(logLines == ["waitingNotices: not a boolean, using default true"])
  }

  @Test func editorAppIsRead() {
    let (file, logLines) = parse(#"{ "editorApp": "com.microsoft.VSCode" }"#)
    #expect(file.editorApp == "com.microsoft.VSCode")
    #expect(logLines.isEmpty)
  }

  @Test func editorAppEmptyFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "editorApp": "" }"#)
    #expect(file.editorApp == nil)
    #expect(logLines == ["editorApp: expected a non-empty string, ignoring it"])
  }

  @Test func editorAppWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "editorApp": 3 }"#)
    #expect(file.editorApp == nil)
    #expect(logLines == ["editorApp: expected a non-empty string, ignoring it"])
  }

  @Test func readsEveryQuitBehavior() {
    #expect(parse(#"{ "quitBehavior": "ask" }"#).file.quitBehavior == .ask)
    #expect(parse(#"{ "quitBehavior": "keepShowing" }"#).file.quitBehavior == .keepShowing)
    #expect(parse(#"{ "quitBehavior": "pause" }"#).file.quitBehavior == .pause)
  }

  @Test func quitBehaviorOutsideItsChoicesFallsBackToDefault() {
    let expected = [
      #"quitBehavior: expected "ask", "keepShowing" or "pause", using default "ask""#
    ]
    let (file, logLines) = parse(#"{ "quitBehavior": "Pause" }"#)
    #expect(file.quitBehavior == nil)
    #expect(logLines == expected)
    let (wrongType, wrongTypeLines) = parse(#"{ "quitBehavior": true }"#)
    #expect(wrongType.quitBehavior == nil)
    #expect(wrongTypeLines == expected)
  }

  @Test func quitBehaviorIsNotAHostKey() {
    let (file, logLines) = parse(#"{ "hosts": { "codex": { "quitBehavior": "pause" } } }"#)
    #expect(file.codex == ConfigFile.HostOverrides())
    #expect(logLines == [#"unknown key "hosts.codex.quitBehavior", ignored"#])
  }

  @Test func readsEveryModeAfterPlan() {
    #expect(parse(#"{ "modeAfterPlan": "default" }"#).file.modeAfterPlan == .default)
    #expect(parse(#"{ "modeAfterPlan": "acceptEdits" }"#).file.modeAfterPlan == .acceptEdits)
    #expect(parse(#"{ "modeAfterPlan": "auto" }"#).file.modeAfterPlan == .auto)
  }

  @Test func modeAfterPlanOutsideItsChoicesFallsBackToDefault() {
    let expected = [
      #"modeAfterPlan: expected "default", "acceptEdits" or "auto", using default "default""#
    ]
    let (file, logLines) = parse(#"{ "modeAfterPlan": "Auto" }"#)
    #expect(file.modeAfterPlan == nil)
    #expect(logLines == expected)
    let (wrongType, wrongTypeLines) = parse(#"{ "modeAfterPlan": true }"#)
    #expect(wrongType.modeAfterPlan == nil)
    #expect(wrongTypeLines == expected)
  }

  @Test func modeAfterPlanIsNotAHostKey() {
    let (file, logLines) = parse(#"{ "hosts": { "codex": { "modeAfterPlan": "auto" } } }"#)
    #expect(file.codex == ConfigFile.HostOverrides())
    #expect(logLines == [#"unknown key "hosts.codex.modeAfterPlan", ignored"#])
  }

  @Test func readsEveryAppearance() {
    #expect(parse(#"{ "appearance": "system" }"#).file.appearance == .system)
    #expect(parse(#"{ "appearance": "light" }"#).file.appearance == .light)
    #expect(parse(#"{ "appearance": "dark" }"#).file.appearance == .dark)
  }

  @Test func appearanceOutsideItsChoicesFallsBackToDefault() {
    let expected = [
      #"appearance: expected "system", "light" or "dark", using default "system""#
    ]
    let (file, logLines) = parse(#"{ "appearance": "Dark" }"#)
    #expect(file.appearance == nil)
    #expect(logLines == expected)
    let (wrongType, wrongTypeLines) = parse(#"{ "appearance": 1 }"#)
    #expect(wrongType.appearance == nil)
    #expect(wrongTypeLines == expected)
  }

  @Test func readsAnAccentColorInEitherCase() {
    #expect(
      parse(##"{ "accentColor": "#a78bfa" }"##).file.accentColor == AccentPreset.purple.color)
    #expect(
      parse(##"{ "accentColor": "#123456" }"##).file.accentColor
        == HexColor(red: 0x12, green: 0x34, blue: 0x56))
  }

  @Test func accentColorThatIsNotHexFallsBackToDefault() {
    let expected = [##"accentColor: expected "#RRGGBB", using default "#E6B04A""##]
    for json in [
      #"{ "accentColor": "blue" }"#, ##"{ "accentColor": "#5B9CF" }"##,
      #"{ "accentColor": 5 }"#,
    ] {
      let (file, logLines) = parse(json)
      #expect(file.accentColor == nil)
      #expect(logLines == expected)
    }
  }

  @Test func appearanceAndAccentColorAreNotHostKeys() {
    let (file, logLines) = parse(
      ##"{ "hosts": { "claude": { "appearance": "dark", "accentColor": "#5B9CF6" } } }"##)
    #expect(file.claude == ConfigFile.HostOverrides())
    #expect(
      Set(logLines) == [
        #"unknown key "hosts.claude.appearance", ignored"#,
        #"unknown key "hosts.claude.accentColor", ignored"#,
      ])
  }

  @Test func ignoresSchemaKey() {
    let (file, logLines) = parse(
      """
      { "$schema": "https://example.com/schema.json" }
      """)
    #expect(file == ConfigFile())
    #expect(logLines.isEmpty)
  }

  @Test func armDelayOutOfRangeClampsAndLogs() {
    let (file, logLines) = parse(#"{ "armDelay": 9 }"#)
    #expect(file.armDelay == 3)
    #expect(logLines == ["armDelay: 9 is out of range 0...3, clamped to 3"])
  }

  @Test func armDelayBelowRangeClampsAndLogs() {
    let (file, logLines) = parse(#"{ "armDelay": -1 }"#)
    #expect(file.armDelay == 0)
    #expect(logLines == ["armDelay: -1 is out of range 0...3, clamped to 0"])
  }

  @Test func armDelayWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "armDelay": "soon" }"#)
    #expect(file.armDelay == nil)
    #expect(logLines == ["armDelay: not a number, using default 0.5"])
  }

  @Test func chainedArmDelayOutOfRangeClampsAndLogs() {
    let (file, logLines) = parse(#"{ "chainedArmDelay": 9 }"#)
    #expect(file.chainedArmDelay == 3)
    #expect(logLines == ["chainedArmDelay: 9 is out of range 0...3, clamped to 3"])
  }

  @Test func chainedArmDelayBelowRangeClampsAndLogs() {
    let (file, logLines) = parse(#"{ "chainedArmDelay": -0.5 }"#)
    #expect(file.chainedArmDelay == 0)
    #expect(logLines == ["chainedArmDelay: -0.5 is out of range 0...3, clamped to 0"])
  }

  @Test func chainedArmDelayWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "chainedArmDelay": "soon" }"#)
    #expect(file.chainedArmDelay == nil)
    #expect(logLines == ["chainedArmDelay: not a number, using default 0.1"])
  }

  @Test func chainedArmDelayZeroIsKept() {
    let (file, logLines) = parse(#"{ "chainedArmDelay": 0 }"#)
    #expect(file.chainedArmDelay == 0)
    #expect(logLines.isEmpty)
  }

  @Test func aBadChainedArmDelayLeavesTheOtherKeysAlone() {
    let (file, logLines) = parse(#"{ "chainedArmDelay": true, "armDelay": 1 }"#)
    #expect(file.chainedArmDelay == nil)
    #expect(file.armDelay == 1)
    #expect(logLines == ["chainedArmDelay: not a number, using default 0.1"])
  }

  @Test func idleSecondsNegativeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "idleSeconds": -1 }"#)
    #expect(file.idleSeconds == nil)
    #expect(logLines == ["idleSeconds: not a non-negative number, using default 5"])
  }

  @Test func idleSecondsWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "idleSeconds": true }"#)
    #expect(file.idleSeconds == nil)
    #expect(logLines == ["idleSeconds: not a non-negative number, using default 5"])
  }

  @Test func graceSecondsNegativeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "graceSeconds": -0.5 }"#)
    #expect(file.graceSeconds == nil)
    #expect(logLines == ["graceSeconds: not a non-negative number, using default 0"])
  }

  @Test func handoffAppsWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "handoffApps": "com.apple.Terminal" }"#)
    #expect(file.handoffApps == nil)
    #expect(logLines == ["handoffApps: not an array, using default []"])
  }

  @Test func handoffAppsWithNonStringElementFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "handoffApps": ["ok", 1] }"#)
    #expect(file.handoffApps == nil)
    #expect(logLines == ["handoffApps: contains a non-string value, using default []"])
  }

  @Test func snoozeMinutesWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "snoozeMinutes": "soon" }"#)
    #expect(file.snoozePresets == nil)
    #expect(
      logLines == ["snoozeMinutes: expected 1 to 6 durations, using default 1m, 5m, 15m, 30m"])
  }

  @Test func snoozeMinutesEmptyFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "snoozeMinutes": [] }"#)
    #expect(file.snoozePresets == nil)
    #expect(
      logLines == ["snoozeMinutes: expected 1 to 6 durations, using default 1m, 5m, 15m, 30m"])
  }

  @Test func snoozeMinutesTooManyFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "snoozeMinutes": [1, 2, 3, 4, 5, 6, 7] }"#)
    #expect(file.snoozePresets == nil)
    #expect(
      logLines == ["snoozeMinutes: expected 1 to 6 durations, using default 1m, 5m, 15m, 30m"])
  }

  @Test func snoozeMinutesOutOfRangeElementFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "snoozeMinutes": [1, 1441] }"#)
    #expect(file.snoozePresets == nil)
    #expect(
      logLines == [
        "snoozeMinutes: expected durations from 10s to 24h, using default 1m, 5m, 15m, 30m"
      ])
  }

  @Test func snoozeMinutesKeepsGivenOrder() {
    let (file, logLines) = parse(#"{ "snoozeMinutes": [30, 1, 15] }"#)
    #expect(file.snoozePresets == [1800, 60, 900])
    #expect(logLines.isEmpty)
  }

  @Test func checkForUpdatesWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "checkForUpdates": "yes" }"#)
    #expect(file.checkForUpdates == nil)
    #expect(logLines == ["checkForUpdates: not a boolean, using default false"])
  }

  @Test func readsShowSkills() {
    let (file, logLines) = parse(#"{ "showSkills": false }"#)
    #expect(file.showSkills == false)
    #expect(logLines.isEmpty)
  }

  @Test func showSkillsIsAbsentWhenNotWritten() {
    let (file, logLines) = parse("{}")
    #expect(file.showSkills == nil)
    #expect(logLines.isEmpty)
  }

  @Test func showSkillsWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "showSkills": "no" }"#)
    #expect(file.showSkills == nil)
    #expect(logLines == ["showSkills: not a boolean, using default true"])
  }

  @Test func includeHeadlessSessionsWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "includeHeadlessSessions": 1 }"#)
    #expect(file.includeHeadlessSessions == nil)
    #expect(logLines == ["includeHeadlessSessions: not a boolean, using default false"])
  }

  @Test func questionNotesWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "questionNotes": "yes" }"#)
    #expect(file.questionNotes == nil)
    #expect(logLines == ["questionNotes: not a boolean, using default false"])
  }

  @Test func questionNotesTrueIsRead() {
    let (file, logLines) = parse(#"{ "questionNotes": true }"#)
    #expect(file.questionNotes == true)
    #expect(logLines.isEmpty)
  }

  @Test func unknownTopLevelKeyIsLoggedAndIgnored() {
    let (file, logLines) = parse(#"{ "bogus": true }"#)
    #expect(file == ConfigFile())
    #expect(logLines == ["unknown key \"bogus\", ignored"])
  }

  @Test func hostsBlockParsesClaudeAndCodex() {
    let (file, logLines) = parse(
      """
      {
        "hosts": {
          "claude": { "armDelay": 1, "idleSeconds": 3 },
          "codex": {
            "graceSeconds": 2, "handoffApps": ["com.apple.Terminal"], "chainedArmDelay": 0.2
          }
        }
      }
      """)
    #expect(logLines.isEmpty)
    #expect(file.claude?.armDelay == 1)
    #expect(file.claude?.chainedArmDelay == nil)
    #expect(file.claude?.idleSeconds == 3)
    #expect(file.codex?.chainedArmDelay == 0.2)
    #expect(file.codex?.graceSeconds == 2)
    #expect(file.codex?.handoffApps == ["com.apple.Terminal"])
  }

  @Test func hostsBlockParsesCursor() {
    let (file, logLines) = parse(
      #"{ "hosts": { "cursor": { "idleSeconds": 2, "handoffApps": ["com.todesktop.230313mzl4w4u92"] } } }"#
    )
    #expect(logLines.isEmpty)
    #expect(file.cursor?.idleSeconds == 2)
    #expect(file.cursor?.handoffApps == ["com.todesktop.230313mzl4w4u92"])
    #expect(file.claude == nil)
    #expect(file.codex == nil)
    let (typo, typoLines) = parse(#"{ "hosts": { "cursor": { "armDelay": "x", "bogus": 1 } } }"#)
    #expect(typo.cursor == ConfigFile.HostOverrides())
    #expect(
      Set(typoLines)
        == [
          "hosts.cursor.armDelay: not a number, using default 0.5",
          "unknown key \"hosts.cursor.bogus\", ignored",
        ])
  }

  @Test func hostsBlockParsesAntigravity() {
    let (file, logLines) = parse(
      #"{ "hosts": { "antigravity": { "graceSeconds": 1, "handoffApps": ["com.apple.Terminal"] } } }"#
    )
    #expect(logLines.isEmpty)
    #expect(file.antigravity?.graceSeconds == 1)
    #expect(file.antigravity?.handoffApps == ["com.apple.Terminal"])
    #expect(file.cursor == nil)
    let (typo, typoLines) = parse(
      #"{ "hosts": { "antigravity": { "idleSeconds": -1, "bogus": 1 }, "gemini": {} } }"#)
    #expect(typo.antigravity == ConfigFile.HostOverrides())
    #expect(
      Set(typoLines)
        == [
          "hosts.antigravity.idleSeconds: not a non-negative number, using default 5",
          "unknown key \"hosts.antigravity.bogus\", ignored",
          "unknown key \"hosts.gemini\", ignored",
        ])
  }

  @Test func picksTheOverridesForEachHost() {
    let file = ConfigFile(
      claude: ConfigFile.HostOverrides(idleSeconds: 1),
      codex: ConfigFile.HostOverrides(idleSeconds: 2),
      cursor: ConfigFile.HostOverrides(idleSeconds: 3),
      antigravity: ConfigFile.HostOverrides(idleSeconds: 4))
    #expect(file.overrides(for: .claude)?.idleSeconds == 1)
    #expect(file.overrides(for: .codex)?.idleSeconds == 2)
    #expect(file.overrides(for: .cursor)?.idleSeconds == 3)
    #expect(file.overrides(for: .antigravity)?.idleSeconds == 4)
    #expect(ConfigFile().overrides(for: .cursor) == nil)
    #expect(ConfigFile().overrides(for: .antigravity) == nil)
  }

  @Test func hostsBlockWrongTypeIsLoggedAndIgnored() {
    let (file, logLines) = parse(#"{ "hosts": "claude" }"#)
    #expect(file.claude == nil)
    #expect(file.codex == nil)
    #expect(logLines == ["hosts: expected an object, ignored"])
  }

  @Test func hostBlockWrongTypeIsLoggedAndIgnored() {
    let (file, logLines) = parse(#"{ "hosts": { "claude": "nope" } }"#)
    #expect(file.claude == nil)
    #expect(logLines == ["hosts.claude: expected an object, ignored"])
  }

  @Test func unknownKeyInHostsIsLoggedAndIgnored() {
    let (file, logLines) = parse(#"{ "hosts": { "chatgpt": {} } }"#)
    #expect(file.claude == nil)
    #expect(file.codex == nil)
    #expect(logLines == ["unknown key \"hosts.chatgpt\", ignored"])
  }

  @Test func unknownKeyInsideHostBlockIsLoggedAndIgnored() {
    let (file, logLines) = parse(#"{ "hosts": { "claude": { "bogus": 1 } } }"#)
    #expect(file.claude == ConfigFile.HostOverrides())
    #expect(logLines == ["unknown key \"hosts.claude.bogus\", ignored"])
  }

  @Test func hostArmDelayOutOfRangeClampsAndLogs() {
    let (file, logLines) = parse(#"{ "hosts": { "codex": { "armDelay": 9 } } }"#)
    #expect(file.codex?.armDelay == 3)
    #expect(logLines == ["hosts.codex.armDelay: 9 is out of range 0...3, clamped to 3"])
  }

  @Test func hostChainedArmDelayOutOfRangeClampsAndLogs() {
    let (file, logLines) = parse(#"{ "hosts": { "claude": { "chainedArmDelay": 4 } } }"#)
    #expect(file.claude?.chainedArmDelay == 3)
    #expect(logLines == ["hosts.claude.chainedArmDelay: 4 is out of range 0...3, clamped to 3"])
  }

  @Test func hostChainedArmDelayWrongTypeFallsBackToDefault() {
    let (file, logLines) = parse(#"{ "hosts": { "codex": { "chainedArmDelay": [1] } } }"#)
    #expect(file.codex?.chainedArmDelay == nil)
    #expect(logLines == ["hosts.codex.chainedArmDelay: not a number, using default 0.1"])
  }

  @Test func brokenJSONFallsBackToAllDefaults() {
    let (file, logLines) = parse("{ not json")
    #expect(file == ConfigFile())
    #expect(logLines == ["config.json is not valid JSON, using defaults"])
  }

  @Test func nonObjectJSONFallsBackToAllDefaults() {
    let (file, logLines) = parse("[1, 2, 3]")
    #expect(file == ConfigFile())
    #expect(logLines == ["config.json does not contain a JSON object, using defaults"])
  }

  @Test func missingFileIsNormalWithNoLog() {
    let home = URL(fileURLWithPath: "/tmp/countersign-config-test-\(UUID().uuidString)")
    let paths = AppPaths(home: home)
    let (file, logLines) = ConfigFileLoader.load(paths: paths)
    #expect(file == ConfigFile())
    #expect(logLines.isEmpty)
  }

  @Test func loadsFromDiskAtTheXDGPath() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "countersign-config-test-\(UUID().uuidString)")
    let xdgConfigHome = root.appendingPathComponent("xdg-config")
    try FileManager.default.createDirectory(
      at: xdgConfigHome.appendingPathComponent("countersign"), withIntermediateDirectories: true)
    let configFile = xdgConfigHome.appendingPathComponent("countersign/config.json")
    try Data(#"{ "armDelay": 1.2 }"#.utf8).write(to: configFile)
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = AppPaths(
      home: root.appendingPathComponent("home"), xdgConfigHome: xdgConfigHome.path)
    let (file, logLines) = ConfigFileLoader.load(paths: paths)
    #expect(file.armDelay == 1.2)
    #expect(logLines.isEmpty)
  }

  @Test func unreadableFileIsLoggedAndFallsBackToDefaults() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "countersign-config-test-\(UUID().uuidString)")
    let configDirectory = root.appendingPathComponent(".config/countersign")
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let paths = AppPaths(home: root)
    try Data(#"{ "armDelay": 1 }"#.utf8).write(to: paths.configFile)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o000], ofItemAtPath: paths.configFile.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644], ofItemAtPath: paths.configFile.path)
      try? FileManager.default.removeItem(at: root)
    }

    let (file, logLines) = ConfigFileLoader.load(paths: paths)
    #expect(file == ConfigFile())
    #expect(logLines == ["config.json could not be read, using defaults"])
  }
}
