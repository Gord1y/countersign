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

  @Test func refreshLeavesAFileWithoutOurEntryUnchanged() throws {
    #expect(try refresh(othersPrompt) == othersPrompt)
    #expect(try refresh("{}") == "{}")
    #expect(try refresh("") == "")
  }

  @Test func refreshRewritesAStaleEntry() throws {
    #expect(try refresh(staleEntry) == freshContext)
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
          command: "countersign hook --host claude", isAsync: true, timeoutSeconds: 3600),
        ContextHookEntry(
          command: "/x/countersign hook --host claude", isAsync: false, timeoutSeconds: nil),
      ])
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
}
