import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"

private func install(
  _ text: String?, host: ApprovalCore.Host = .claude, path: String = brewPath
) throws -> String {
  let bytes = try HookSetup.install(
    into: text.map { Array($0.utf8) }, host: host, executablePath: path)
  return String(decoding: bytes, as: UTF8.self)
}

private func uninstall(_ text: String?, host: ApprovalCore.Host = .claude) throws -> String? {
  try HookSetup.uninstall(from: text.map { Array($0.utf8) }, host: host).map {
    String(decoding: $0, as: UTF8.self)
  }
}

private func reindented(_ text: String, unit: String) -> String {
  text.components(separatedBy: "\n").map { line in
    let spaces = line.prefix { $0 == " " }.count
    return String(repeating: unit, count: spaces / 2) + line.dropFirst(spaces)
  }.joined(separator: "\n")
}

private let claudeSettings = """
  {
    "model": "opus",
    "permissions": {
      "allow": [
        "Bash(git status)"
      ]
    },
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "~/bin/guard.sh"
            }
          ]
        }
      ]
    },
    "statusLine": {
      "type": "command",
      "command": "~/bin/status.sh"
    }
  }

  """

private let claudeSettingsInstalled = """
  {
    "model": "opus",
    "permissions": {
      "allow": [
        "Bash(git status)"
      ]
    },
    "hooks": {
      "PreToolUse": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "~/bin/guard.sh"
            }
          ]
        }
      ],
      "PermissionRequest": [
        {
          "matcher": "",
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude",
              "timeout": 3600
            }
          ]
        }
      ]
    },
    "statusLine": {
      "type": "command",
      "command": "~/bin/status.sh"
    }
  }

  """

private let freshClaude = """
  {
    "hooks": {
      "PermissionRequest": [
        {
          "matcher": "",
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude",
              "timeout": 3600
            }
          ]
        }
      ]
    }
  }

  """

private let freshCodex = """
  {
    "hooks": {
      "PermissionRequest": [
        {
          "matcher": "",
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host codex",
              "timeout": 3600,
              "statusMessage": "Waiting for the approval panel"
            }
          ]
        }
      ]
    }
  }

  """

private let oldEntry = """
  {
    "hooks": {
      "PermissionRequest": [
        {
          "matcher": "",
          "hooks": [
            {
              "type": "command",
              "command": "/Users/dev/.local/bin/countersign hook --host claude --grace 3",
              "timeout": 600
            }
          ]
        }
      ]
    }
  }

  """

private let otherPermissionHook = """
  {
    "hooks": {
      "PermissionRequest": [
        {
          "matcher": "Bash",
          "hooks": [
            {
              "type": "command",
              "command": "~/bin/log-permission.sh"
            }
          ]
        }
      ]
    }
  }

  """

@Suite struct HookSetupTests {
  @Test func createsTheClaudeFileWhenItIsMissing() throws {
    #expect(try install(nil) == freshClaude)
  }

  @Test func createsTheCodexFileWithItsStatusMessage() throws {
    #expect(try install(nil, host: .codex) == freshCodex)
  }

  @Test func treatsABlankFileAsEmpty() throws {
    #expect(try install("") == freshClaude)
    #expect(try install(" \n\t\n") == freshClaude)
  }

  @Test func expandsAnEmptyObjectKeepingTheMissingTrailingNewline() throws {
    #expect(try install("{}") == String(freshClaude.dropLast()))
    #expect(try install("{}\n") == freshClaude)
  }

  @Test func addsTheEventBesideOtherHooksAndKeepsEveryOtherKey() throws {
    #expect(try install(claudeSettings) == claudeSettingsInstalled)
  }

  @Test func addsTheHooksKeyAfterTheLastTopLevelKey() throws {
    let settings = "{\n  \"model\": \"opus\",\n  \"env\": {\n    \"A\": \"1\"\n  }\n}\n"
    let expected = """
      {
        "model": "opus",
        "env": {
          "A": "1"
        },
        "hooks": {
          "PermissionRequest": [
            {
              "matcher": "",
              "hooks": [
                {
                  "type": "command",
                  "command": "/opt/homebrew/bin/countersign hook --host claude",
                  "timeout": 3600
                }
              ]
            }
          ]
        }
      }

      """
    #expect(try install(settings) == expected)
  }

  @Test func addsTheEventToAnEmptyHooksObject() throws {
    let settings = "{\n  \"hooks\": {}\n}\n"
    #expect(try install(settings) == freshClaude)
  }

  @Test func appendsAGroupBesideSomeoneElsesPermissionHook() throws {
    let expected = """
      {
        "hooks": {
          "PermissionRequest": [
            {
              "matcher": "Bash",
              "hooks": [
                {
                  "type": "command",
                  "command": "~/bin/log-permission.sh"
                }
              ]
            },
            {
              "matcher": "",
              "hooks": [
                {
                  "type": "command",
                  "command": "/opt/homebrew/bin/countersign hook --host claude",
                  "timeout": 3600
                }
              ]
            }
          ]
        }
      }

      """
    #expect(try install(otherPermissionHook) == expected)
  }

  @Test func rewritesOurOldEntryInPlaceToTheCanonicalCommand() throws {
    #expect(try install(oldEntry) == freshClaude)
  }

  @Test func rewritesAnEntryWhoseArgumentsDifferInAnyWay() throws {
    for command in [
      "/opt/homebrew/bin/countersign hook --host codex",
      "/opt/homebrew/bin/countersign hook",
      "countersign hook --host claude extra",
    ] {
      let settings = freshClaude.replacingOccurrences(
        of: "/opt/homebrew/bin/countersign hook --host claude", with: command)
      #expect(try install(settings) == freshClaude)
    }
  }

  @Test func addsTheMissingTimeoutAndStatusMessageToOurEntry() throws {
    let settings = """
      {
        "hooks": {
          "PermissionRequest": [
            {
              "matcher": "",
              "hooks": [
                {
                  "type": "command",
                  "command": "countersign hook --host codex"
                }
              ]
            }
          ]
        }
      }
      """
    #expect(try install(settings, host: .codex) == String(freshCodex.dropLast()))
  }

  @Test func replacesAStaleStatusMessage() throws {
    let settings = freshCodex.replacingOccurrences(
      of: "Waiting for the approval panel", with: "Waiting")
    #expect(try install(settings, host: .codex) == freshCodex)
  }

  @Test func keepsATimeoutThatIsAlreadyRightHoweverItIsSpelled() throws {
    let settings = freshClaude.replacingOccurrences(of: "3600", with: "3.6e3")
    #expect(try install(settings) == settings)
  }

  @Test func updatesEveryEntryOfOursAndOnlyOurs() throws {
    let settings = """
      {"hooks": {"PermissionRequest": [
        {"matcher": "", "hooks": [{"type": "command", "command": "/old/countersign hook --host claude", "timeout": 3600}]},
        {"matcher": "Bash", "hooks": [
          {"type": "command", "command": "~/bin/other.sh"},
          {"type": "command", "command": "'/old dir/countersign' hook --host claude", "timeout": 3600}
        ]}
      ]}}
      """
    let expected = settings.replacingOccurrences(of: "/old/countersign", with: brewPath)
      .replacingOccurrences(of: "'/old dir/countersign'", with: brewPath)
    #expect(try install(settings) == expected)
  }

  @Test func keepsAQuotedPathThatAlreadyMatches() throws {
    let settings = freshClaude.replacingOccurrences(
      of: "\"/opt/homebrew/bin/countersign hook", with: "\"'/opt/homebrew/bin/countersign' hook")
    #expect(try install(settings) == settings)
  }

  @Test func quotesAPathWithSpacesInTheCommand() throws {
    let result = try install(nil, path: "/Users/me/My Tools/countersign")
    #expect(result.contains("\"command\": \"'/Users/me/My Tools/countersign' hook --host claude\""))
    #expect(try install(result, path: "/Users/me/My Tools/countersign") == result)
  }

  @Test func leavesAHookOfAnotherTypeAlone() throws {
    let settings = """
      {
        "hooks": {
          "PermissionRequest": [
            {
              "matcher": "",
              "hooks": [
                {
                  "type": "prompt",
                  "command": "countersign hook --host claude"
                }
              ]
            }
          ]
        }
      }
      """
    let expected = """
      {
        "hooks": {
          "PermissionRequest": [
            {
              "matcher": "",
              "hooks": [
                {
                  "type": "prompt",
                  "command": "countersign hook --host claude"
                }
              ]
            },
            {
              "matcher": "",
              "hooks": [
                {
                  "type": "command",
                  "command": "/opt/homebrew/bin/countersign hook --host claude",
                  "timeout": 3600
                }
              ]
            }
          ]
        }
      }
      """
    #expect(try install(settings) == expected)
  }

  @Test func preservesCarriageReturnLineFeeds() throws {
    let settings = claudeSettings.replacingOccurrences(of: "\n", with: "\r\n")
    let expected = claudeSettingsInstalled.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(try install(settings) == expected)
  }

  @Test func preservesTabs() throws {
    let settings = reindented(claudeSettings, unit: "\t")
    #expect(try install(settings) == reindented(claudeSettingsInstalled, unit: "\t"))
  }

  @Test func preservesFourSpaceIndentation() throws {
    let settings = reindented(claudeSettings, unit: "    ")
    #expect(try install(settings) == reindented(claudeSettingsInstalled, unit: "    "))
  }

  @Test func preservesAMissingTrailingNewline() throws {
    let settings = String(claudeSettings.dropLast())
    #expect(try install(settings) == String(claudeSettingsInstalled.dropLast()))
  }

  @Test func preservesEscapesAndFindsEscapedKeys() throws {
    let settings = """
      {
        "note": "caf\\u00e9 \\ud83d\\ude00 \\/ caf\u{E9}",
        "hook\\u0073": {
          "PermissionRequest": [
            {
              "matcher": "",
              "hooks": [
                {
                  "type": "command",
                  "command": "\\/old\\/countersign hook --host claude",
                  "timeout": 3600
                }
              ]
            }
          ]
        }
      }
      """
    let expected = settings.replacingOccurrences(
      of: "\\/old\\/countersign hook", with: "/opt/homebrew/bin/countersign hook")
    #expect(try install(settings) == expected)
    let escapedCanonical = expected.replacingOccurrences(
      of: "/opt/homebrew/bin/countersign hook --host claude",
      with: "\\/opt\\/homebrew\\/bin\\/countersign hook\\u0020--host claude")
    #expect(try install(escapedCanonical) == escapedCanonical)
  }

  @Test func copiesTheKeyAndColonSpacing() throws {
    let settings = "{\n  \"model\" : \"opus\"\n}"
    let result = try install(settings)
    #expect(result.contains("\"hooks\" : {"))
    #expect(result.contains("\"timeout\" : 3600"))
  }

  @Test func appendsToAnObjectWrittenOnOneLine() throws {
    let result = try install("{ \"model\": \"opus\" }")
    #expect(result.hasPrefix("{ \"model\": \"opus\", \"hooks\": {\n  \"PermissionRequest\": ["))
    #expect(result.hasSuffix("\n  ]\n} }"))
    #expect(try install(result) == result)
  }

  @Test func installingTwiceChangesNothingTheSecondTime() throws {
    let inputs: [String?] = [
      nil, "{}", claudeSettings, oldEntry, otherPermissionHook,
      claudeSettings.replacingOccurrences(of: "\n", with: "\r\n"),
      reindented(claudeSettings, unit: "\t"),
    ]
    for input in inputs {
      for host in ApprovalCore.Host.allCases {
        let once = try install(input, host: host)
        #expect(try install(once, host: host) == once)
      }
    }
  }

  @Test func leavesInvalidJSONUntouched() {
    let invalid = [
      "{\n  " + String(repeating: "/", count: 2) + " my settings\n  \"model\": \"opus\"\n}",
      "{\"model\": \"opus\",}",
      "{\"model\": \"opus\"",
    ]
    for text in invalid {
      #expect(throws: JSONSpanError.self) { try install(text) }
      #expect(throws: JSONSpanError.self) { try uninstall(text) }
    }
  }

  @Test func reportsAnUnexpectedShape() {
    #expect(throws: HookSetupError.unexpectedType(key: "the top level", expected: "an object")) {
      try install("[]")
    }
    #expect(throws: HookSetupError.unexpectedType(key: "hooks", expected: "an object")) {
      try install("{\"hooks\": []}")
    }
    #expect(
      throws: HookSetupError.unexpectedType(key: "hooks.PermissionRequest", expected: "an array")
    ) {
      try install("{\"hooks\": {\"PermissionRequest\": {}}}")
    }
    #expect(throws: HookSetupError.unexpectedType(key: "the top level", expected: "an object")) {
      try uninstall("\"text\"")
    }
    #expect(throws: HookSetupError.unexpectedType(key: "hooks", expected: "an object")) {
      try uninstall("{\"hooks\": 1}")
    }
    #expect(
      throws: HookSetupError.unexpectedType(key: "hooks.PermissionRequest", expected: "an array")
    ) {
      try uninstall("{\"hooks\": {\"PermissionRequest\": null}}")
    }
  }

  @Test func refusesAnExecutableItCouldNotFindAgain() {
    let path = "/Applications/Countersign.app/Contents/MacOS/Countersign"
    #expect(throws: HookSetupError.unrecognizableExecutable(path)) {
      try install(nil, path: path)
    }
  }

  @Test func describesItsErrors() {
    #expect(
      HookSetupError.unexpectedType(key: "hooks", expected: "an object").description
        == "hooks is not an object")
    #expect(
      HookSetupError.unrecognizableExecutable("/x/other").description
        == "/x/other is not named countersign, so its entry could not be found again")
  }

  @Test func uninstallRestoresTheFileItInstalledInto() throws {
    #expect(try uninstall(claudeSettingsInstalled) == claudeSettings)
    let tabs = reindented(claudeSettingsInstalled, unit: "\t")
    #expect(try uninstall(tabs) == reindented(claudeSettings, unit: "\t"))
  }

  @Test func uninstallLeavesAnEmptyHooksObject() throws {
    #expect(try uninstall(freshClaude) == "{\n  \"hooks\": {}\n}\n")
    #expect(try uninstall(freshCodex, host: .codex) == "{\n  \"hooks\": {}\n}\n")
  }

  @Test func uninstallRemovesOnlyOurGroup() throws {
    let installed = try install(otherPermissionHook)
    #expect(try uninstall(installed) == otherPermissionHook)
  }

  @Test func uninstallKeepsAGroupThatStillHasOtherHooks() throws {
    let settings = """
      {"hooks": {"PermissionRequest": [{"matcher": "", "hooks": [
        {"type": "command", "command": "~/bin/other.sh"},
        {"type": "command", "command": "countersign hook --host claude"}
      ]}]}}
      """
    let expected = """
      {"hooks": {"PermissionRequest": [{"matcher": "", "hooks": [
        {"type": "command", "command": "~/bin/other.sh"}
      ]}]}}
      """
    #expect(try uninstall(settings) == expected)
  }

  @Test func uninstallRemovesEveryEntryOfOurs() throws {
    let settings = """
      {"hooks": {"PermissionRequest": [
        {"matcher": "", "hooks": [{"type": "command", "command": "countersign hook --host claude"}]},
        {"matcher": "Bash", "hooks": [{"type": "command", "command": "~/bin/other.sh"}]},
        {"matcher": "", "hooks": [{"type": "command", "command": "/x/countersign hook"}]}
      ], "Stop": []}}
      """
    let expected = """
      {"hooks": {"PermissionRequest": [
        {"matcher": "Bash", "hooks": [{"type": "command", "command": "~/bin/other.sh"}]}
      ], "Stop": []}}
      """
    #expect(try uninstall(settings) == expected)
  }

  @Test func uninstallChangesNothingWithoutOurEntry() throws {
    #expect(try uninstall(nil) == nil)
    #expect(try uninstall("") == "")
    #expect(try uninstall("{}") == "{}")
    #expect(try uninstall(claudeSettings) == claudeSettings)
    #expect(try uninstall(otherPermissionHook) == otherPermissionHook)
    #expect(try uninstall("{\"hooks\": {\"Stop\": []}}") == "{\"hooks\": {\"Stop\": []}}")
  }

  @Test func findsOurSitesAndSkipsMalformedGroups() throws {
    let text = """
      {"hooks": {"PermissionRequest": [1, {"hooks": 2}, {"hooks": [3, {"type": "command", "command": "countersign hook"}]}]}}
      """
    let root = try JSONSpanReader.parse(Array(text.utf8))
    let sites = HookSetup.sites(in: root)
    #expect(sites.count == 1)
    #expect(sites.first?.groupIndex == 2)
    #expect(sites.first?.hookIndex == 1)
    #expect(sites.first?.eventMemberIndex == 0)
    #expect(HookSetup.sites(in: try JSONSpanReader.parse(Array("{}".utf8))).isEmpty)
  }

  @Test func claudeInstallRefreshesAStaleUserPromptSubmitEntryButNeverAddsOne() throws {
    let stale = """
      {"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/old/countersign hook --host claude"}]}]}}
      """
    let refreshed = try install(stale)
    #expect(
      refreshed.contains(
        "{\"type\": \"command\", \"command\": \"/opt/homebrew/bin/countersign hook --host claude\", \"async\": true, \"timeout\": 3600}"
      ))
    #expect(refreshed.contains("\"PermissionRequest\""))
    #expect(try install(refreshed) == refreshed)
    #expect(!(try install(claudeSettings)).contains("UserPromptSubmit"))
    #expect(!(try install(nil, host: .codex)).contains("UserPromptSubmit"))
    let codexPrompt = stale.replacingOccurrences(of: "--host claude", with: "--host codex")
    #expect(!(try install(codexPrompt, host: .codex)).contains("async"))
  }

  @Test func claudeUninstallRemovesTheEntriesOfBothEvents() throws {
    let settings = """
      {"hooks": {
        "PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "countersign hook --host claude"}]}],
        "UserPromptSubmit": [
          {"hooks": [{"type": "command", "command": "~/bin/prompt-log.sh"}]},
          {"hooks": [{"type": "command", "command": "countersign hook --host claude", "async": true}]}
        ]
      }}
      """
    let removed = try #require(try uninstall(settings))
    #expect(removed.contains("~/bin/prompt-log.sh"))
    #expect(!removed.contains("countersign"))
    #expect(!removed.contains("PermissionRequest"))
    let onlyPrompt =
      "{\"hooks\": {\"UserPromptSubmit\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"countersign hook\"}]}]}}"
    #expect(try uninstall(onlyPrompt) == "{\"hooks\": {}}")
    let codex = try #require(try uninstall(settings, host: .codex))
    #expect(codex.contains("UserPromptSubmit"))
    #expect(codex.contains("countersign hook --host claude\", \"async\""))
  }

  @Test func acceptsOnlyYesAsConfirmation() {
    #expect(HookSetup.isConfirmation("y"))
    #expect(HookSetup.isConfirmation("Y"))
    #expect(HookSetup.isConfirmation("yes"))
    #expect(HookSetup.isConfirmation(" YeS \r"))
    #expect(!HookSetup.isConfirmation(""))
    #expect(!HookSetup.isConfirmation("n"))
    #expect(!HookSetup.isConfirmation("yep"))
    #expect(!HookSetup.isConfirmation(nil))
  }

  @Test func buildsTheEntryShapes() {
    #expect(
      HookSetup.hookFragment(host: .claude, executablePath: brewPath)
        == .object([
          JSONFragmentMember(key: "type", value: .string("command")),
          JSONFragmentMember(
            key: "command", value: .string("/opt/homebrew/bin/countersign hook --host claude")),
          JSONFragmentMember(key: "timeout", value: .integer(3600)),
        ]))
    #expect(HookSetup.isBlank(Array(" \r\n\t".utf8)))
    #expect(!HookSetup.isBlank(Array("{}".utf8)))
  }
}
