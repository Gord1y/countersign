import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"

private func install(
  _ text: String?, host: ApprovalCore.Host = .claude, path: String = brewPath
) throws -> String {
  let bytes = try WaitingHookSetup.install(
    into: text.map { Array($0.utf8) }, host: host, executablePath: path)
  return String(decoding: bytes, as: UTF8.self)
}

private func refresh(_ text: String, host: ApprovalCore.Host = .claude) throws -> String {
  let bytes = try WaitingHookSetup.refresh(
    into: Array(text.utf8), host: host, executablePath: brewPath)
  return String(decoding: bytes, as: UTF8.self)
}

private func uninstall(_ text: String?, host: ApprovalCore.Host = .claude) throws -> String? {
  try WaitingHookSetup.uninstall(from: text.map { Array($0.utf8) }, host: host).map {
    String(decoding: $0, as: UTF8.self)
  }
}

private let freshWaiting = """
  {
    "hooks": {
      "Stop": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude --event waiting",
              "async": true,
              "timeout": 30
            }
          ]
        }
      ]
    }
  }

  """

private let ourEntries = """
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
      ],
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

private let staleWaiting = """
  {
    "hooks": {
      "Stop": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "/old/place/countersign hook --host claude --event waiting",
              "timeout": 5
            }
          ]
        }
      ]
    }
  }

  """

private let sharedStopGroup = """
  {
    "hooks": {
      "Stop": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "~/bin/notify.sh"
            },
            {
              "type": "command",
              "command": "/opt/homebrew/bin/countersign hook --host claude --event waiting",
              "async": true,
              "timeout": 30
            }
          ]
        }
      ]
    }
  }

  """

private let ownStopOnly = """
  {
    "hooks": {
      "Stop": [
        {
          "hooks": [
            {
              "type": "command",
              "command": "~/bin/notify.sh"
            }
          ]
        }
      ]
    }
  }

  """

@Suite struct WaitingHookSetupTests {
  @Test func installsIntoEmptyBytes() throws {
    #expect(try install(nil) == freshWaiting)
    #expect(try install("") == freshWaiting)
  }

  @Test func installsNextToThePermissionAndPromptEntriesWithoutTouchingThem() throws {
    let installed = try install(ourEntries)
    #expect(installed.contains("\"Stop\": ["))
    #expect(
      try HookSetup.removeEntries(
        from: Array(installed.utf8), event: WaitingHookSetup.eventName
      ).map { String(decoding: $0, as: UTF8.self) } == ourEntries)
  }

  @Test func installingTwiceChangesNothing() throws {
    let once = try install(ourEntries)
    #expect(try install(once) == once)
    #expect(try install(nil) == freshWaiting)
    #expect(try install(freshWaiting) == freshWaiting)
  }

  @Test func refreshFixesAStaleCommandPathAndAMissingAsync() throws {
    let refreshed = try refresh(staleWaiting)
    #expect(
      refreshed.contains(
        "\"command\": \"/opt/homebrew/bin/countersign hook --host claude --event waiting\""))
    #expect(refreshed.contains("\"async\": true"))
    #expect(refreshed.contains("\"timeout\": 30"))
    #expect(!refreshed.contains("/old/place"))
  }

  @Test func refreshNeverAddsAnEntry() throws {
    #expect(try refresh(ourEntries) == ourEntries)
    #expect(try refresh("{}\n") == "{}\n")
    #expect(try refresh("") == "")
  }

  @Test func uninstallRemovesOnlyOurStopHookAndKeepsTheUsersOwn() throws {
    #expect(try uninstall(sharedStopGroup) == ownStopOnly)
    #expect(try uninstall(ownStopOnly) == ownStopOnly)
  }

  @Test func uninstallOfAFreshInstallLeavesAnEmptyHooksObject() throws {
    let removed = try #require(try uninstall(freshWaiting))
    #expect(WaitingHookSetup.entries(in: Array(removed.utf8), host: .claude).isEmpty)
    #expect(try uninstall(nil) == nil)
  }

  @Test func listsTheEntryItWrote() throws {
    let entries = WaitingHookSetup.entries(in: Array(freshWaiting.utf8), host: .claude)
    #expect(
      entries == [
        ContextHookEntry(
          command: "/opt/homebrew/bin/countersign hook --host claude --event waiting",
          isAsync: true, timeoutSeconds: 30)
      ])
    #expect(WaitingHookSetup.entries(in: Array(ownStopOnly.utf8), host: .claude).isEmpty)
    #expect(WaitingHookSetup.entries(in: Array("nope".utf8), host: .claude).isEmpty)
  }

  @Test func supportsAllFourHosts() {
    #expect(Set(WaitingHookSetup.supportedHosts) == Set(ApprovalCore.Host.allCases))
  }

  @Test func rejectsAnExecutableThatIsNotCountersign() {
    #expect(throws: HookSetupError.self) { try install(nil, path: "/usr/bin/other") }
  }

  @Test func setupRefreshesAnExistingStopEntryButNeverAddsOne() throws {
    let refreshed = try HookSetup.install(
      into: Array(staleWaiting.utf8), host: .claude, executablePath: brewPath)
    let text = String(decoding: refreshed, as: UTF8.self)
    #expect(text.contains("/opt/homebrew/bin/countersign hook --host claude --event waiting"))
    #expect(text.contains("\"PermissionRequest\""))
    let fresh = try HookSetup.install(into: nil, host: .claude, executablePath: brewPath)
    #expect(
      !String(decoding: fresh, as: UTF8.self).contains("\"Stop\""))
  }

  @Test func uninstallingClaudeRemovesAllThreeEvents() throws {
    let all = try WaitingHookSetup.install(
      into: Array(ourEntries.utf8), host: .claude, executablePath: brewPath)
    let removed = try #require(try HookSetup.uninstall(from: all, host: .claude))
    let text = String(decoding: removed, as: UTF8.self)
    #expect(!text.contains("countersign"))
    #expect(!text.contains("\"Stop\""))
    #expect(!text.contains("\"UserPromptSubmit\""))
    #expect(!text.contains("\"PermissionRequest\""))
  }
}
