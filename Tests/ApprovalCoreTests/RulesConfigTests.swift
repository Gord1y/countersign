import Foundation
import Testing

@testable import ApprovalCore

@Suite struct RulesConfigTests {
  private func parse(_ json: String) -> (file: ConfigFile, logLines: [String]) {
    ConfigFileParser.parse(Data(json.utf8))
  }

  @Test func aValidListRoundTripsIntoSettings() {
    let (file, logLines) = parse(
      """
      {
        "rules": [
          { "decision": "allow", "agent": "cursor", "project": "~/code/shop",
            "tool": "Shell", "command": "pnpm lint" },
          { "decision": "deny", "command": "rm:-rf *", "message": "No." }
        ]
      }
      """)
    #expect(logLines.isEmpty)
    let expected = [
      ApprovalRule(
        decision: .allow, agent: .cursor, project: "~/code/shop", tool: "Shell",
        command: "pnpm lint"),
      ApprovalRule(decision: .deny, command: "rm:-rf *", message: "No."),
    ]
    #expect(file.rules == expected)
    #expect(Settings.resolve(file: file, host: .claude).rules == expected)
    #expect(Settings.resolve(file: file, host: .cursor).rules == expected)
  }

  @Test func noRulesKeyMeansAnEmptyList() {
    let (file, logLines) = parse("{}")
    #expect(file.rules == nil)
    #expect(logLines.isEmpty)
    #expect(Settings.resolve(file: file, host: .claude).rules.isEmpty)
  }

  @Test func rulesThatIsNotAnArrayIsIgnored() {
    let (file, logLines) = parse(#"{ "rules": {} }"#)
    #expect(file.rules == nil)
    #expect(logLines == ["rules: not an array, ignored"])
  }

  @Test func anEntryThatIsNotAnObjectIsDropped() {
    let (file, logLines) = parse(#"{ "rules": ["allow"] }"#)
    #expect(file.rules == [])
    #expect(logLines == ["rules[0]: expected an object, dropped"])
  }

  @Test func anUnknownKeyIsIgnoredAndTheEntryKept() {
    let (file, logLines) = parse(#"{ "rules": [{ "decision": "allow", "when": "now" }] }"#)
    #expect(file.rules == [ApprovalRule(decision: .allow)])
    #expect(logLines == ["unknown key \"rules[0].when\", ignored"])
  }

  @Test func aMissingOrBadDecisionDropsTheEntry() {
    let (file, logLines) = parse(
      #"{ "rules": [{ "command": "ls" }, { "decision": "ask" }, { "decision": 1 }] }"#)
    #expect(file.rules == [])
    #expect(
      logLines == [
        "rules[0].decision: expected \"allow\" or \"deny\", dropped",
        "rules[1].decision: expected \"allow\" or \"deny\", dropped",
        "rules[2].decision: expected \"allow\" or \"deny\", dropped",
      ])
  }

  @Test func aBadAgentDropsTheEntry() {
    let (file, logLines) = parse(#"{ "rules": [{ "decision": "allow", "agent": "gemini" }] }"#)
    #expect(file.rules == [])
    #expect(
      logLines == [
        "rules[0].agent: expected \"claude\", \"codex\", \"cursor\" or \"antigravity\", dropped"
      ])
  }

  @Test func aBadStringFieldDropsTheEntry() {
    for key in ["project", "tool", "command", "message"] {
      let value = key == "project" ? #""/a""# : #""x""#
      let good = #"{ "decision": "deny", "\#(key)": \#(value) }"#
      let empty = #"{ "decision": "deny", "\#(key)": "" }"#
      let number = #"{ "decision": "deny", "\#(key)": 3 }"#
      let (file, logLines) = parse(#"{ "rules": [\#(empty), \#(number), \#(good)] }"#)
      #expect(file.rules?.count == 1)
      #expect(
        logLines == [
          "rules[0].\(key): expected a non-empty string, dropped",
          "rules[1].\(key): expected a non-empty string, dropped",
        ])
    }
  }

  @Test func aProjectMustBeAbsoluteOrStartWithATilde() {
    let (file, logLines) = parse(
      #"{ "rules": [{ "decision": "allow", "project": "code/shop" }, { "decision": "allow", "project": "~" }] }"#
    )
    #expect(file.rules == [ApprovalRule(decision: .allow, project: "~")])
    #expect(
      logLines == [
        "rules[0].project: expected an absolute path or one starting with ~, dropped"
      ])
  }

  @Test func aMessageOnAnAllowRuleIsDroppedAndTheRuleKept() {
    let (file, logLines) = parse(
      #"{ "rules": [{ "decision": "allow", "command": "ls", "message": "hi" }] }"#)
    #expect(file.rules == [ApprovalRule(decision: .allow, command: "ls")])
    #expect(logLines == ["rules[0].message: only used by deny rules, ignored"])
  }

  @Test func droppedEntriesDoNotShiftTheKeptOrder() {
    let (file, logLines) = parse(
      """
      { "rules": [
        { "decision": "allow", "command": "first" },
        { "decision": "nope" },
        { "decision": "deny", "command": "second" },
        7,
        { "decision": "allow", "command": "third" }
      ] }
      """)
    #expect(
      file.rules == [
        ApprovalRule(decision: .allow, command: "first"),
        ApprovalRule(decision: .deny, command: "second"),
        ApprovalRule(decision: .allow, command: "third"),
      ])
    #expect(logLines.count == 2)
  }

  @Test func rulesIsAKnownTopLevelKeyAndNotAHostKey() {
    #expect(ConfigFileParser.topLevelKeys.contains("rules"))
    #expect(!ConfigFileParser.hostKeys.contains("rules"))
    let (_, logLines) = parse(#"{ "rules": [] }"#)
    #expect(logLines.isEmpty)
  }
}
