import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"

private func install(_ text: String?, path: String = brewPath) throws -> String {
  let bytes = try HookSetup.install(
    into: text.map { Array($0.utf8) }, host: .cursor, executablePath: path,
    addsWaitingEntry: false)
  return String(decoding: bytes, as: UTF8.self)
}

private func uninstall(_ text: String?) throws -> String? {
  try HookSetup.uninstall(from: text.map { Array($0.utf8) }, host: .cursor).map {
    String(decoding: $0, as: UTF8.self)
  }
}

private func root(_ text: String) throws -> JSONSpanNode {
  try JSONSpanReader.parse(Array(text.utf8))
}

private let freshCursor = """
  {
    "version": 1,
    "hooks": {
      "beforeShellExecution": [
        {
          "command": "/opt/homebrew/bin/countersign hook --host cursor",
          "timeout": 3600
        }
      ],
      "beforeMCPExecution": [
        {
          "command": "/opt/homebrew/bin/countersign hook --host cursor",
          "timeout": 3600
        }
      ]
    }
  }

  """

private let otherTools = """
  {
    "version": 1,
    "hooks": {
      "beforeShellExecution": [
        {
          "command": "./hooks/audit.sh"
        }
      ],
      "afterFileEdit": [
        {
          "command": "./hooks/format.sh",
          "timeout": 30
        }
      ]
    }
  }

  """

private let otherToolsInstalled = """
  {
    "version": 1,
    "hooks": {
      "beforeShellExecution": [
        {
          "command": "./hooks/audit.sh"
        },
        {
          "command": "/opt/homebrew/bin/countersign hook --host cursor",
          "timeout": 3600
        }
      ],
      "afterFileEdit": [
        {
          "command": "./hooks/format.sh",
          "timeout": 30
        }
      ],
      "beforeMCPExecution": [
        {
          "command": "/opt/homebrew/bin/countersign hook --host cursor",
          "timeout": 3600
        }
      ]
    }
  }

  """

private let oldEntries = """
  {
    "version": 1,
    "hooks": {
      "beforeShellExecution": [
        {
          "command": "/Users/dev/.local/bin/countersign hook --host cursor --verbose",
          "timeout": 30
        }
      ],
      "beforeMCPExecution": [
        {
          "command": "/Users/dev/.local/bin/countersign hook --host claude"
        }
      ]
    }
  }

  """

@Suite struct CursorHookSetupTests {
  @Test func createsTheFileWithItsVersionWhenItIsMissing() throws {
    #expect(try install(nil) == freshCursor)
    #expect(try install("") == freshCursor)
    #expect(try install(" \n\t\n") == freshCursor)
    #expect(try install("{}\n") == freshCursor)
  }

  @Test func addsOurEntryBesideEveryoneElsesAndKeepsTheirs() throws {
    #expect(try install(otherTools) == otherToolsInstalled)
  }

  @Test func keepsAVersionThatIsAlreadyThere() throws {
    let settings = otherTools.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
    let expected = otherToolsInstalled.replacingOccurrences(
      of: "\"version\": 1", with: "\"version\": 2")
    #expect(try install(settings) == expected)
  }

  @Test func addsTheVersionWhenAFileHasHooksButNoVersion() throws {
    let settings = "{\n  \"hooks\": {}\n}\n"
    let result = try install(settings)
    #expect(result.hasPrefix("{\n  \"hooks\": {\n    \"beforeShellExecution\": ["))
    #expect(result.hasSuffix("  },\n  \"version\": 1\n}\n"))
    #expect(try install(result) == result)
  }

  @Test func rewritesOurOldEntriesInPlaceToTheCanonicalCommand() throws {
    #expect(try install(oldEntries) == freshCursor)
  }

  @Test func addsOurEntryToTheEventThatLacksIt() throws {
    let settings = """
      {
        "version": 1,
        "hooks": {
          "beforeMCPExecution": [],
          "beforeShellExecution": [
            {
              "command": "/opt/homebrew/bin/countersign hook --host cursor",
              "timeout": 3600
            }
          ]
        }
      }
      """
    let expected = """
      {
        "version": 1,
        "hooks": {
          "beforeMCPExecution": [
            {
              "command": "/opt/homebrew/bin/countersign hook --host cursor",
              "timeout": 3600
            }
          ],
          "beforeShellExecution": [
            {
              "command": "/opt/homebrew/bin/countersign hook --host cursor",
              "timeout": 3600
            }
          ]
        }
      }
      """
    #expect(try install(settings) == expected)
  }

  @Test func recognisesACommandTypeAndLeavesAPromptAlone() throws {
    let typed = freshCursor.replacingOccurrences(
      of: "{\n        \"command\"", with: "{\n        \"type\": \"command\",\n        \"command\"")
    #expect(try install(typed) == typed)
    let prompt = """
      {"version": 1, "hooks": {"beforeShellExecution": [{"type": "prompt", "command": "countersign hook --host cursor"}], "beforeMCPExecution": []}}
      """
    let result = try install(prompt)
    #expect(
      result.contains("{\"type\": \"prompt\", \"command\": \"countersign hook --host cursor\"}"))
    #expect(try CursorHookSetup.sites(in: root(result)).count == 2)
  }

  @Test func installingTwiceChangesNothingTheSecondTime() throws {
    let inputs: [String?] = [
      nil, "{}", otherTools, oldEntries, "{\"hooks\": {}}",
      otherTools.replacingOccurrences(of: "\n", with: "\r\n"),
    ]
    for input in inputs {
      let once = try install(input)
      #expect(try install(once) == once)
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
      throws: HookSetupError.unexpectedType(key: "hooks.beforeMCPExecution", expected: "an array")
    ) {
      try install("{\"hooks\": {\"beforeMCPExecution\": {}}}")
    }
    #expect(throws: HookSetupError.unexpectedType(key: "the top level", expected: "an object")) {
      try uninstall("\"text\"")
    }
    #expect(throws: HookSetupError.unexpectedType(key: "hooks", expected: "an object")) {
      try uninstall("{\"hooks\": 1}")
    }
    #expect(
      throws: HookSetupError.unexpectedType(key: "hooks.beforeShellExecution", expected: "an array")
    ) {
      try uninstall("{\"hooks\": {\"beforeShellExecution\": null}}")
    }
    #expect(throws: JSONSpanError.self) { try install("{\"version\": 1,}") }
    #expect(throws: JSONSpanError.self) { try uninstall("{\"version\": 1,}") }
  }

  @Test func refusesAnExecutableItCouldNotFindAgain() {
    let path = "/Applications/Countersign.app/Contents/MacOS/Countersign"
    #expect(throws: HookSetupError.unrecognizableExecutable(path)) {
      try install(nil, path: path)
    }
  }

  @Test func uninstallRestoresTheFileItInstalledInto() throws {
    #expect(try uninstall(otherToolsInstalled) == otherTools)
    let crlf = otherToolsInstalled.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(try uninstall(crlf) == otherTools.replacingOccurrences(of: "\n", with: "\r\n"))
  }

  @Test func uninstallKeepsTheVersionAndAnEmptyHooksObject() throws {
    #expect(try uninstall(freshCursor) == "{\n  \"version\": 1,\n  \"hooks\": {}\n}\n")
  }

  @Test func uninstallRemovesEveryEntryOfOursAndOnlyOurs() throws {
    let settings = """
      {"hooks": {
        "beforeShellExecution": [{"command": "countersign hook --host cursor"}, {"command": "./audit.sh"}, {"command": "/x/countersign hook"}],
        "beforeMCPExecution": [{"command": "countersign hook --host cursor"}],
        "preToolUse": [{"command": "countersign hook --host cursor"}]
      }}
      """
    let expected = """
      {"hooks": {
        "beforeShellExecution": [{"command": "./audit.sh"}],
        "preToolUse": [{"command": "countersign hook --host cursor"}]
      }}
      """
    #expect(try uninstall(settings) == expected)
  }

  @Test func uninstallChangesNothingWithoutOurEntry() throws {
    #expect(try uninstall(nil) == nil)
    #expect(try uninstall("") == "")
    #expect(try uninstall("{}") == "{}")
    #expect(try uninstall(otherTools) == otherTools)
    #expect(try uninstall("{\"hooks\": {\"stop\": []}}") == "{\"hooks\": {\"stop\": []}}")
  }

  @Test func findsOurEntriesUnderBothEventsOnly() throws {
    let text = """
      {"hooks": {
        "stop": [{"command": "countersign hook"}],
        "beforeMCPExecution": [1, {"command": 2}, {"command": "countersign hook"}],
        "beforeShellExecution": {"command": "countersign hook"}
      }}
      """
    let sites = CursorHookSetup.sites(in: try root(text))
    #expect(sites.count == 1)
    #expect(sites.first?.eventName == "beforeMCPExecution")
    #expect(sites.first?.entryIndex == 2)
    #expect(sites.first?.eventMemberIndex == 1)
    #expect(CursorHookSetup.missingEvents(in: try root(text)) == ["beforeShellExecution"])
    #expect(CursorHookSetup.sites(in: try root("{}")).isEmpty)
    #expect(
      CursorHookSetup.missingEvents(in: try root("{}"))
        == ["beforeShellExecution", "beforeMCPExecution"])
    #expect(CursorHookSetup.missingEvents(in: try root(freshCursor)).isEmpty)
  }

  @Test func buildsTheEntryShape() {
    #expect(
      CursorHookSetup.entryFragment(executablePath: brewPath)
        == .object([
          JSONFragmentMember(
            key: "command", value: .string("/opt/homebrew/bin/countersign hook --host cursor")),
          JSONFragmentMember(key: "timeout", value: .integer(3600)),
        ]))
  }
}
