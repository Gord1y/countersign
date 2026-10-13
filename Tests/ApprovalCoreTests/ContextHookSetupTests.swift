import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"

private func install(_ text: String?, path: String = brewPath) throws -> String {
  let bytes = try ContextHookSetup.install(into: text.map { Array($0.utf8) }, executablePath: path)
  return String(decoding: bytes, as: UTF8.self)
}

private func refresh(_ text: String) throws -> String {
  let bytes = try ContextHookSetup.refresh(into: Array(text.utf8), executablePath: brewPath)
  return String(decoding: bytes, as: UTF8.self)
}

private func uninstall(_ text: String?) throws -> String? {
  try ContextHookSetup.uninstall(from: text.map { Array($0.utf8) }).map {
    String(decoding: $0, as: UTF8.self)
  }
}

private let promptOnlyContext = """
  {
    "hooks": {
      "UserPromptSubmit": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude",
              "async": true,
              "timeout": 3600
            }
          ]
        }
      ]
    }
  }

  """

private let freshContext = """
  {
    "hooks": {
      "UserPromptSubmit": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude",
              "async": true,
              "timeout": 3600
            }
          ]
        }
      ],
      "PostToolUse": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude",
              "async": true,
              "timeout": 3600
            }
          ]
        }
      ]
    }
  }

  """

private let othersPrompt = """
  {
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
      "UserPromptSubmit": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "~/bin/prompt-log.sh"
            }
          ]
        }
      ]
    }
  }

  """

private let othersPromptWithOurs = """
  {
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
      "UserPromptSubmit": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "~/bin/prompt-log.sh"
            }
          ]
        },
        {
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude",
              "async": true,
              "timeout": 3600
            }
          ]
        }
      ],
      "PostToolUse": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude",
              "async": true,
              "timeout": 3600
            }
          ]
        }
      ]
    }
  }

  """

private let staleEntry = """
  {
    "hooks": {
      "UserPromptSubmit": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/Users/dev/.local/bin/countersign hook --host claude"
            }
          ]
        }
      ]
    }
  }

  """

@Suite struct ContextHookSetupTests {
  @Test func installsIntoAMissingBlankOrEmptyFile() throws {
    #expect(try install(nil) == freshContext)
    #expect(try install("") == freshContext)
    #expect(try install(" \n\t\n") == freshContext)
    #expect(try install("{}\n") == freshContext)
    #expect(try install("{}") == String(freshContext.dropLast()))
  }

  @Test func appendsBesideSomeoneElsesUserPromptSubmitGroup() throws {
    #expect(try install(othersPrompt) == othersPromptWithOurs)
  }

  @Test func refreshesOurExistingEntryAndAddsAsyncAndTimeout() throws {
    #expect(try install(staleEntry) == freshContext)
    let once = try install(staleEntry)
    #expect(try install(once) == once)
    #expect(try install(freshContext) == freshContext)
  }

  @Test func addsTheEventBesideOtherEventsWhenHooksExists() throws {
    let settings = "{\n  \"hooks\": {\n    \"Stop\": []\n  }\n}\n"
    let result = try install(settings)
    #expect(result.contains("\"Stop\": [],\n    \"UserPromptSubmit\": ["))
    #expect(try install(result) == result)
  }

  @Test func addsTheToolEventBesideAnExistingPromptEntryAndKeepsItsBytes() throws {
    let result = try install(promptOnlyContext)
    #expect(result == freshContext)
    #expect(result.hasPrefix(String(promptOnlyContext.dropLast("\n    }\n  }\n\n".count))))
    #expect(try install(result) == result)
  }

  @Test func installsEachEventAsAnAsyncGroupWithoutAMatcher() throws {
    let result = try install(nil)
    let root = try JSONSpanReader.parse(Array(result.utf8))
    for event in ContextHookSetup.eventNames {
      let site = try #require(HookSetup.sites(in: root, event: event).first)
      #expect(ContextHookSetup.isAsync(site.hook))
      #expect(site.hook.member(named: "timeout")?.value.numberValue == 3600)
      #expect(site.groups.elements?.first?.member(named: "matcher") == nil)
    }
  }

  @Test func refreshNeverAddsTheToolEvent() throws {
    #expect(try refresh(promptOnlyContext) == promptOnlyContext)
  }

  @Test func uninstallKeepsSomeoneElsesToolHook() throws {
    let others = """
      {"hooks": {"PostToolUse": [{"hooks": [{"type": "command", "command": "~/bin/after.sh"}]}]}}
      """
    let installed = try install(others)
    let removed = try #require(try uninstall(installed))
    #expect(removed.contains("~/bin/after.sh"))
    #expect(!removed.contains("countersign"))
    #expect(!removed.contains("UserPromptSubmit"))
  }

  @Test func refreshLeavesAFileWithoutOurEntryUnchanged() throws {
    #expect(try refresh(othersPrompt) == othersPrompt)
    #expect(try refresh("{}") == "{}")
    #expect(try refresh("") == "")
  }

  @Test func refreshRewritesAStaleEntry() throws {
    #expect(try refresh(staleEntry) == promptOnlyContext)
  }

  @Test func refreshKeepsATimeoutThatIsAlreadyRightHoweverItIsSpelled() throws {
    let settings = freshContext.replacingOccurrences(of: "3600", with: "3.6e3")
    #expect(try refresh(settings) == settings)
  }

  @Test func uninstallRestoresTheFileItInstalledInto() throws {
    #expect(try uninstall(othersPromptWithOurs) == othersPrompt)
    let base = "{\n  \"model\": \"opus\"\n}\n"
    let installed = try install(base)
    #expect(try uninstall(installed) == "{\n  \"model\": \"opus\",\n  \"hooks\": {}\n}\n")
  }

  @Test func uninstallLeavesAnEmptyHooksObjectAndChangesNothingWithoutOurEntry() throws {
    #expect(try uninstall(freshContext) == "{\n  \"hooks\": {}\n}\n")
    #expect(try uninstall(nil) == nil)
    #expect(try uninstall("") == "")
    #expect(try uninstall(othersPrompt) == othersPrompt)
  }

  @Test func recognisesOnlyCommandHooksOfOursUnderTheEvent() throws {
    let settings = """
      {"hooks": {
        "PermissionRequest": [{"hooks": [{"type": "command", "command": "countersign hook --host claude"}]}],
        "UserPromptSubmit": [
          {"hooks": [
            {"type": "prompt", "command": "countersign hook --host claude"},
            {"type": "command", "command": "~/bin/other.sh"},
            {"type": "command", "command": "countersign hook --host claude", "async": true, "timeout": 3600},
            {"type": "command", "command": "/x/countersign hook --host claude", "async": "yes"}
          ]}
        ]
      }}
      """
    #expect(
      ContextHookSetup.entries(in: Array(settings.utf8)) == [
        ContextHookEntry(
          event: "UserPromptSubmit", command: "countersign hook --host claude", isAsync: true,
          timeoutSeconds: 3600),
        ContextHookEntry(
          event: "UserPromptSubmit", command: "/x/countersign hook --host claude", isAsync: false,
          timeoutSeconds: nil),
      ])
    #expect(
      ContextHookSetup.entries(in: Array(freshContext.utf8)).map(\.event)
        == ["UserPromptSubmit", "PostToolUse"])
    #expect(ContextHookSetup.entries(in: Array("{".utf8)).isEmpty)
    #expect(ContextHookSetup.entries(in: Array("{}".utf8)).isEmpty)
  }

  @Test func throwsWhenTheEventIsNotAnArray() {
    #expect(
      throws: HookSetupError.unexpectedType(key: "hooks.UserPromptSubmit", expected: "an array")
    ) {
      try install("{\"hooks\": {\"UserPromptSubmit\": {}}}")
    }
    #expect(
      throws: HookSetupError.unexpectedType(key: "hooks.UserPromptSubmit", expected: "an array")
    ) {
      try uninstall("{\"hooks\": {\"UserPromptSubmit\": null}}")
    }
    #expect(throws: HookSetupError.unexpectedType(key: "hooks", expected: "an object")) {
      try install("{\"hooks\": []}")
    }
    #expect(throws: HookSetupError.unexpectedType(key: "the top level", expected: "an object")) {
      try install("[]")
    }
  }

  @Test func refusesAnExecutableItCouldNotFindAgain() {
    let path = "/Applications/Countersign.app/Contents/MacOS/Countersign"
    #expect(throws: HookSetupError.unrecognizableExecutable(path)) {
      try install(nil, path: path)
    }
  }

  @Test func codexRefreshUpdatesTheTimeoutAndLeavesAnExistingAsyncMemberAlone() throws {
    let stale = """
      {"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\(brewPath) hook --host codex", "async": true, "timeout": 3600}]}], "PostToolUse": [{"hooks": [{"type": "command", "command": "\(brewPath) hook --host codex", "async": true, "timeout": 3600}]}]}}
      """
    let refreshed = try ContextHookSetup.refresh(
      into: Array(stale.utf8), executablePath: brewPath, host: .codex)
    let expected = stale.replacingOccurrences(of: "\"timeout\": 3600", with: "\"timeout\": 30")
    #expect(String(decoding: refreshed, as: UTF8.self) == expected)
    #expect(String(decoding: refreshed, as: UTF8.self).contains("\"async\": true, \"timeout\": 30"))
  }

  @Test func codexInstallAddsBothGroupsWithoutMatcherOrAsyncAndATimeoutOf30() throws {
    let permission = Array(
      #"{"hooks": {"PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "/opt/homebrew/bin/countersign hook --host codex", "timeout": 3600}]}]}}"#
        .utf8)
    let installed = try ContextHookSetup.install(
      into: permission, executablePath: brewPath, host: .codex)
    let entries = ContextHookSetup.entries(in: installed)
    #expect(entries.map(\.event) == ["UserPromptSubmit", "PostToolUse"])
    #expect(entries.allSatisfy { $0.command == "\(brewPath) hook --host codex" })
    #expect(entries.allSatisfy { !$0.isAsync && $0.timeoutSeconds == 30 })
    let text = String(decoding: installed, as: UTF8.self)
    #expect(!text.contains("async"))
    #expect(text.components(separatedBy: "matcher").count == 2)
    #expect(
      try ContextHookSetup.refresh(into: installed, executablePath: brewPath, host: .codex)
        == installed)
    #expect(
      try ContextHookSetup.refresh(into: permission, executablePath: brewPath, host: .codex)
        == permission)
    let removed = try #require(try ContextHookSetup.uninstall(from: installed))
    #expect(ContextHookSetup.entries(in: removed).isEmpty)
    #expect(String(decoding: removed, as: UTF8.self).contains("PermissionRequest"))
  }
}
