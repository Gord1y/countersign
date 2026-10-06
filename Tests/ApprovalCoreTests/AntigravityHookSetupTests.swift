import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"

private func install(_ text: String?, path: String = brewPath) throws -> String {
  let bytes = try HookSetup.install(
    into: text.map { Array($0.utf8) }, host: .antigravity, executablePath: path,
    addsWaitingEntry: false)
  return String(decoding: bytes, as: UTF8.self)
}

private func uninstall(_ text: String?) throws -> String? {
  try HookSetup.uninstall(from: text.map { Array($0.utf8) }, host: .antigravity).map {
    String(decoding: $0, as: UTF8.self)
  }
}

private func root(_ text: String) throws -> JSONSpanNode {
  try JSONSpanReader.parse(Array(text.utf8))
}

private func namedHook(_ text: String) throws -> JSONSpanNode {
  try #require(try root(text).member(named: "countersign")?.value)
}

private let freshAntigravity = """
  {
    "countersign": {
      "PreToolUse": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host antigravity",
              "timeout": 3600
            }
          ]
        }
      ]
    }
  }

  """

private let otherHooks = """
  {
    "audit": {
      "enabled": true,
      "PreToolUse": [
        {
          "matcher": "run_command",
          "hooks": [
            {
              "type": "command",
              "command": "~/.gemini/hooks/audit.sh",
              "timeout": 30
            }
          ]
        }
      ],
      "Stop": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "~/.gemini/hooks/notify.sh"
            }
          ]
        }
      ]
    }
  }

  """

private let otherHooksInstalled = """
  {
    "audit": {
      "enabled": true,
      "PreToolUse": [
        {
          "matcher": "run_command",
          "hooks": [
            {
              "type": "command",
              "command": "~/.gemini/hooks/audit.sh",
              "timeout": 30
            }
          ]
        }
      ],
      "Stop": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "~/.gemini/hooks/notify.sh"
            }
          ]
        }
      ]
    },
    "countersign": {
      "PreToolUse": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host antigravity",
              "timeout": 3600
            }
          ]
        }
      ]
    }
  }

  """

private let oldEntry = """
  {
    "countersign": {
      "PreToolUse": [
        {
          "matcher": "*",
          "hooks": [
            {
              "type": "command",
              "command": "/Users/dev/.local/bin/countersign hook --host antigravity --verbose",
              "timeout": 30
            }
          ]
        }
      ]
    }
  }

  """

@Suite struct AntigravityHookSetupTests {
  @Test func createsTheNamedHookWhenTheFileIsMissing() throws {
    #expect(try install(nil) == freshAntigravity)
    #expect(try install("") == freshAntigravity)
    #expect(try install(" \n\t\n") == freshAntigravity)
    #expect(try install("{}\n") == freshAntigravity)
  }

  @Test func writesExactlyTheShapeAntigravityAccepts() throws {
    let hook = try namedHook(try install(nil))
    let entry = try #require(AntigravityHookSetup.entry(inSetupShape: hook))
    #expect(entry.member(named: "type")?.value.stringValue == "command")
    #expect(
      entry.member(named: "command")?.value.stringValue
        == "/opt/homebrew/bin/countersign hook --host antigravity")
    #expect(entry.member(named: "timeout")?.value.numberValue == 3600)
    #expect(entry.members?.map(\.key) == ["type", "command", "timeout"])
  }

  @Test func addsOurNamedHookBesideEveryoneElsesAndKeepsTheirs() throws {
    #expect(try install(otherHooks) == otherHooksInstalled)
  }

  @Test func rewritesOurEntryInPlaceToTheCanonicalCommand() throws {
    #expect(try install(oldEntry) == freshAntigravity)
  }

  @Test func addsATimeoutThatIsMissing() throws {
    let settings = """
      {"countersign": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "\(brewPath) hook --host antigravity"}]}]}}
      """
    let expected = """
      {"countersign": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "\(brewPath) hook --host antigravity", "timeout": 3600}]}]}}
      """
    #expect(try install(settings) == expected)
  }

  @Test func rewritesANamedHookOfOursInAnyOtherShape() throws {
    let misshapen = [
      "{\"countersign\": {\"enabled\": false, \"PreToolUse\": [{\"matcher\": \"*\", \"hooks\": [{\"type\": \"command\", \"command\": \"\(brewPath) hook --host antigravity\", \"timeout\": 3600}]}]}}",
      "{\"countersign\": {\"PreToolUse\": [{\"matcher\": \"run_command\", \"hooks\": [{\"type\": \"command\", \"command\": \"\(brewPath) hook --host antigravity\", \"timeout\": 3600}]}]}}",
      "{\"countersign\": {\"PreToolUse\": [{\"matcher\": \"*\", \"hooks\": [{\"type\": \"command\", \"command\": \"\(brewPath) hook --host antigravity\", \"timeout\": 3600, \"statusMessage\": \"x\"}]}]}}",
      "{\"countersign\": {\"PreToolUse\": [{\"matcher\": \"*\", \"hooks\": [{\"type\": \"command\", \"timeout\": 3600}]}]}}",
      "{\"countersign\": {\"Stop\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"\(brewPath) hook --host antigravity\"}]}]}}",
      "{\"countersign\": {\"PreToolUse\": [{\"matcher\": \"*\", \"hooks\": []}]}}",
      "{\"countersign\": {\"PreToolUse\": []}}",
      "{\"countersign\": []}",
      "{\"countersign\": null}",
    ]
    let expected = """
      {"countersign": {
        "PreToolUse": [
          {
            "matcher": "*",
            "hooks": [
              {
                "type": "command",
                "command": "/opt/homebrew/bin/countersign hook --host antigravity",
                "timeout": 3600
              }
            ]
          }
        ]
      }}
      """
    for settings in misshapen {
      #expect(try install(settings) == expected)
    }
  }

  @Test func leavesEntriesOfOursInOtherNamedHooksAlone() throws {
    let settings = """
      {"mine": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "countersign hook --host antigravity"}]}]}}
      """
    let installed = try install(settings)
    #expect(installed.hasPrefix(settings.dropLast()))
    #expect(try root(installed).member(named: "countersign") != nil)
    #expect(try uninstall(installed) == settings)
    #expect(AntigravityHookSetup.hookNodes(in: try root(settings)).isEmpty)
  }

  @Test func installingTwiceChangesNothingTheSecondTime() throws {
    let inputs: [String?] = [
      nil, "{}", otherHooks, oldEntry, "{\"countersign\": []}",
      otherHooks.replacingOccurrences(of: "\n", with: "\r\n"),
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
    #expect(throws: HookSetupError.unexpectedType(key: "the top level", expected: "an object")) {
      try uninstall("\"text\"")
    }
    #expect(throws: JSONSpanError.self) { try install("{\"audit\": {},}") }
    #expect(throws: JSONSpanError.self) { try uninstall("{\"audit\": {},}") }
  }

  @Test func refusesAnExecutableItCouldNotFindAgain() {
    let path = "/Applications/Countersign.app/Contents/MacOS/Countersign"
    #expect(throws: HookSetupError.unrecognizableExecutable(path)) {
      try install(nil, path: path)
    }
  }

  @Test func uninstallRestoresTheFileItInstalledInto() throws {
    #expect(try uninstall(otherHooksInstalled) == otherHooks)
    let crlf = otherHooksInstalled.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(try uninstall(crlf) == otherHooks.replacingOccurrences(of: "\n", with: "\r\n"))
  }

  @Test func uninstallLeavesAnEmptyObjectBehind() throws {
    #expect(try uninstall(freshAntigravity) == "{}\n")
  }

  @Test func uninstallRemovesOurNamedHookWhateverItsShape() throws {
    #expect(try uninstall("{\"countersign\": null, \"audit\": {}}") == "{\"audit\": {}}")
    #expect(
      try uninstall("{\"countersign\": {}, \"audit\": {}, \"countersign\": []}")
        == "{\"audit\": {}}")
  }

  @Test func uninstallChangesNothingWithoutOurNamedHook() throws {
    #expect(try uninstall(nil) == nil)
    #expect(try uninstall("") == "")
    #expect(try uninstall("{}") == "{}")
    #expect(try uninstall(otherHooks) == otherHooks)
  }

  @Test func findsOurEntryOnlyInTheSetupShape() throws {
    #expect(AntigravityHookSetup.hookNodes(in: try root(freshAntigravity)).count == 1)
    #expect(AntigravityHookSetup.hookNodes(in: try root(oldEntry)).count == 1)
    #expect(AntigravityHookSetup.hookNodes(in: try root("{}")).isEmpty)
    #expect(AntigravityHookSetup.hookNodes(in: try root("{\"countersign\": {}}")).isEmpty)
    #expect(AntigravityHookSetup.hasNamedHook(in: try root("{\"countersign\": {}}")))
    #expect(!AntigravityHookSetup.hasNamedHook(in: try root(otherHooks)))
    let typeless = freshAntigravity.replacingOccurrences(
      of: "\"type\": \"command\",\n", with: "")
    #expect(AntigravityHookSetup.entry(inSetupShape: try namedHook(typeless)) == nil)
    let twoMatchers = """
      {"countersign": {"PreToolUse": [{"matcher": "*", "matcher": "*"}]}}
      """
    #expect(AntigravityHookSetup.entry(inSetupShape: try namedHook(twoMatchers)) == nil)
    let twoTimeouts = """
      {"countersign": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "countersign hook", "timeout": 1, "timeout": 2}]}]}}
      """
    #expect(AntigravityHookSetup.entry(inSetupShape: try namedHook(twoTimeouts)) == nil)
    let twoGroups = """
      {"countersign": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "countersign hook"}]}, {"matcher": "*", "hooks": []}]}}
      """
    #expect(AntigravityHookSetup.entry(inSetupShape: try namedHook(twoGroups)) == nil)
    let otherTool = """
      {"countersign": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "~/bin/guard.sh"}]}]}}
      """
    #expect(AntigravityHookSetup.entry(inSetupShape: try namedHook(otherTool)) == nil)
  }

  @Test func buildsTheNamedHookShape() {
    #expect(
      AntigravityHookSetup.namedHookFragment(executablePath: brewPath)
        == .object([
          JSONFragmentMember(
            key: "PreToolUse",
            value: .array([
              .object([
                JSONFragmentMember(key: "matcher", value: .string("*")),
                JSONFragmentMember(
                  key: "hooks",
                  value: .array([
                    .object([
                      JSONFragmentMember(key: "type", value: .string("command")),
                      JSONFragmentMember(
                        key: "command",
                        value: .string("/opt/homebrew/bin/countersign hook --host antigravity")),
                      JSONFragmentMember(key: "timeout", value: .integer(3600)),
                    ])
                  ])),
              ])
            ]))
        ]))
    #expect(AntigravityHookSetup.hookName == "countersign")
  }
}
