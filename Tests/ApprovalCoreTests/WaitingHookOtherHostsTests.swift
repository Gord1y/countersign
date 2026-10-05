import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"
private let stalePath = "/old/place/countersign"
private let otherHosts: [ApprovalCore.Host] = [.codex, .cursor, .antigravity]

private func waitingCommand(_ host: ApprovalCore.Host, path: String = brewPath) -> String {
  "\(path) hook --host \(host.rawValue) --event waiting"
}

private func freshWaiting(_ host: ApprovalCore.Host, path: String = brewPath) -> String {
  switch host {
  case .cursor:
    return """
      {
        "version": 1,
        "hooks": {
          "stop": [
            {
              "command": "\(waitingCommand(host, path: path))",
              "timeout": 30
            }
          ]
        }
      }

      """
  case .antigravity:
    return """
      {
        "countersign-waiting": {
          "Stop": [
            {
              "type": "command",
              "command": "\(waitingCommand(host, path: path))",
              "timeout": 30
            }
          ]
        }
      }

      """
  case .claude, .codex:
    return """
      {
        "hooks": {
          "Stop": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "\(waitingCommand(host, path: path))",
                  "timeout": 30
                }
              ]
            }
          ]
        }
      }

      """
  }
}

private func text(_ bytes: [UInt8]?) -> String? {
  bytes.map { String(decoding: $0, as: UTF8.self) }
}

private func permissionFile(_ host: ApprovalCore.Host) throws -> String {
  let bytes = try HookSetup.install(
    into: nil, host: host, executablePath: brewPath, addsWaitingEntry: false)
  return String(decoding: bytes, as: UTF8.self)
}

private func install(_ source: String?, host: ApprovalCore.Host) throws -> String {
  let bytes = try WaitingHookSetup.install(
    into: source.map { Array($0.utf8) }, host: host, executablePath: brewPath)
  return String(decoding: bytes, as: UTF8.self)
}

private func userEntryBesideOurs(_ host: ApprovalCore.Host) -> (shared: String, ownOnly: String) {
  switch host {
  case .cursor:
    let ours = """
      {
            "command": "\(waitingCommand(host))",
            "timeout": 30
          }
      """
    return (
      """
      {
        "version": 1,
        "hooks": {
          "stop": [
            {
              "command": "~/bin/notify.sh"
            },
            \(ours)
          ]
        }
      }

      """,
      """
      {
        "version": 1,
        "hooks": {
          "stop": [
            {
              "command": "~/bin/notify.sh"
            }
          ]
        }
      }

      """
    )
  case .antigravity:
    let mine = """
      "my-notify": {
          "Stop": [
            {
              "type": "command",
              "command": "~/bin/notify.sh"
            }
          ]
        }
      """
    let ours = freshWaiting(host).replacingOccurrences(of: "\n}\n", with: "")
    return (
      ours + ",\n  " + mine + "\n}\n",
      "{\n  " + mine + "\n}\n"
    )
  case .claude, .codex:
    let ours = """
      {
                  "type": "command",
                  "command": "\(waitingCommand(host))",
                  "timeout": 30
                }
      """
    return (
      """
      {
        "hooks": {
          "Stop": [
            {
              "hooks": [
                {
                  "type": "command",
                  "command": "~/bin/notify.sh"
                },
                \(ours)
              ]
            }
          ]
        }
      }

      """,
      """
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
    )
  }
}

@Suite struct WaitingHookOtherHostsTests {
  @Test(arguments: otherHosts)
  func installsIntoEmptyBytes(host: ApprovalCore.Host) throws {
    #expect(try install(nil, host: host) == freshWaiting(host))
    #expect(try install("", host: host) == freshWaiting(host))
    #expect(try install("{}\n", host: host) == freshWaiting(host))
  }

  @Test(arguments: otherHosts)
  func installsNextToThePermissionEntryWithoutTouchingIt(host: ApprovalCore.Host) throws {
    let permission = try permissionFile(host)
    let installed = try install(permission, host: host)
    #expect(installed != permission)
    #expect(installed.contains(waitingCommand(host)))
    #expect(
      text(try WaitingHookSetup.uninstall(from: Array(installed.utf8), host: host)) == permission)
    #expect(
      WaitingHookSetup.entries(in: Array(permission.utf8), host: host).isEmpty)
  }

  @Test(arguments: otherHosts)
  func installingTwiceChangesNothing(host: ApprovalCore.Host) throws {
    let installed = try install(try permissionFile(host), host: host)
    #expect(try install(installed, host: host) == installed)
    #expect(try install(freshWaiting(host), host: host) == freshWaiting(host))
  }

  @Test(arguments: otherHosts)
  func refreshFixesAStaleCommandPathAndNeverAdds(host: ApprovalCore.Host) throws {
    let stale = freshWaiting(host, path: stalePath)
    let refreshed = try WaitingHookSetup.refresh(
      into: Array(stale.utf8), host: host, executablePath: brewPath)
    #expect(text(refreshed) == freshWaiting(host))
    let permission = try permissionFile(host)
    #expect(
      text(
        try WaitingHookSetup.refresh(
          into: Array(permission.utf8), host: host, executablePath: brewPath))
        == permission)
    #expect(
      text(
        try WaitingHookSetup.refresh(into: Array("{}\n".utf8), host: host, executablePath: brewPath)
      )
        == "{}\n")
    #expect(
      text(try WaitingHookSetup.refresh(into: [], host: host, executablePath: brewPath)) == "")
  }

  @Test(arguments: otherHosts)
  func setupRefreshesAnExistingEntryButNeverAddsOne(host: ApprovalCore.Host) throws {
    let withStale = try install(try permissionFile(host), host: host)
      .replacingOccurrences(of: brewPath, with: stalePath)
    let refreshed = try HookSetup.install(
      into: Array(withStale.utf8), host: host, executablePath: brewPath, addsWaitingEntry: false)
    #expect(String(decoding: refreshed, as: UTF8.self).contains(waitingCommand(host)))
    #expect(
      !String(decoding: refreshed, as: UTF8.self).contains(waitingCommand(host, path: stalePath)))
    #expect(!(try permissionFile(host)).contains("--event waiting"))
  }

  @Test(arguments: otherHosts)
  func uninstallRemovesOnlyOurEntryAndKeepsTheUsersOwn(host: ApprovalCore.Host) throws {
    let files = userEntryBesideOurs(host)
    #expect(
      text(try WaitingHookSetup.uninstall(from: Array(files.shared.utf8), host: host))
        == files.ownOnly)
    #expect(
      text(try WaitingHookSetup.uninstall(from: Array(files.ownOnly.utf8), host: host))
        == files.ownOnly)
    #expect(try WaitingHookSetup.uninstall(from: nil, host: host) == nil)
  }

  @Test(arguments: otherHosts)
  func listsTheEntryItWrote(host: ApprovalCore.Host) {
    #expect(
      WaitingHookSetup.entries(in: Array(freshWaiting(host).utf8), host: host) == [
        ContextHookEntry(command: waitingCommand(host), isAsync: false, timeoutSeconds: 30)
      ])
    #expect(WaitingHookSetup.entries(in: Array("nope".utf8), host: host).isEmpty)
  }

  @Test func cursorSetupNeitherTouchesNorDuplicatesTheWaitingEntry() throws {
    let withWaiting = freshWaiting(.cursor)
    let installed = try CursorHookSetup.install(
      into: Array(withWaiting.utf8), executablePath: brewPath)
    let installedText = String(decoding: installed, as: UTF8.self)
    #expect(installedText.components(separatedBy: "--event waiting").count == 2)
    #expect(installedText.contains("\"beforeShellExecution\""))
    #expect(
      text(try WaitingHookSetup.uninstall(from: installed, host: .cursor))
        == String(
          decoding: try CursorHookSetup.install(into: nil, executablePath: brewPath), as: UTF8.self)
    )
    let uninstalled = try #require(
      try CursorHookSetup.uninstall(from: installed).map { String(decoding: $0, as: UTF8.self) })
    #expect(uninstalled.contains(waitingCommand(.cursor)))
    #expect(!uninstalled.contains("beforeShellExecution"))
  }

  @Test func cursorNeverListsStopAmongItsPermissionEvents() {
    #expect(!CursorAdapter.events.contains(WaitingHookSetup.cursorEventName))
  }

  @Test func antigravityKeepsTheOneEventShapeOfTheCountersignHook() throws {
    let both = try install(try permissionFile(.antigravity), host: .antigravity)
    let root = try JSONSpanReader.parse(Array(both.utf8))
    #expect(AntigravityHookSetup.hookNodes(in: root).count == 1)
    let waiting = try #require(root.member(named: "countersign-waiting")?.value)
    #expect(AntigravityHookSetup.entry(inSetupShape: waiting) == nil)
    #expect(AntigravityHookSetup.flatEntry(inSetupShape: waiting, event: "Stop") != nil)
    let ours = try #require(root.member(named: "countersign")?.value)
    #expect(AntigravityHookSetup.entry(inSetupShape: ours) != nil)
    #expect(AntigravityHookSetup.flatEntry(inSetupShape: ours, event: "Stop") == nil)
  }

  @Test func antigravityReplacesAMisshapenWaitingHookOnInstall() throws {
    let misshapen = "{\n  \"countersign-waiting\": {\"Stop\": []}\n}\n"
    #expect(try install(misshapen, host: .antigravity).contains(waitingCommand(.antigravity)))
    #expect(
      WaitingHookSetup.entries(in: Array(misshapen.utf8), host: .antigravity).isEmpty)
  }

  @Test func antigravityReplacesAGroupedStopWithTheFlatOneItAccepts() throws {
    let grouped = """
      {
        "countersign-waiting": {
          "Stop": [
            {
              "matcher": "*",
              "hooks": [
                {
                  "type": "command",
                  "command": "\(waitingCommand(.antigravity))",
                  "timeout": 30
                }
              ]
            }
          ]
        }
      }

      """
    #expect(WaitingHookSetup.entries(in: Array(grouped.utf8), host: .antigravity).isEmpty)
    #expect(try install(grouped, host: .antigravity) == freshWaiting(.antigravity))
  }

  @Test func uninstallingAntigravityRemovesBothNames() throws {
    let both = try install(try permissionFile(.antigravity), host: .antigravity)
    #expect(both.contains("\"countersign\""))
    #expect(both.contains("\"countersign-waiting\""))
    let removed = try #require(
      try HookSetup.uninstall(from: Array(both.utf8), host: .antigravity))
    #expect(String(decoding: removed, as: UTF8.self) == "{}\n")
  }

  @Test func uninstallingCodexAndCursorRemovesTheWaitingEntryToo() throws {
    for host in [ApprovalCore.Host.codex, .cursor] {
      let both = try install(try permissionFile(host), host: host)
      let removed = try #require(try HookSetup.uninstall(from: Array(both.utf8), host: host))
      #expect(!String(decoding: removed, as: UTF8.self).contains("countersign"))
    }
  }

  @Test func rejectsAnExecutableThatIsNotCountersign() {
    for host in otherHosts {
      #expect(throws: HookSetupError.self) {
        try WaitingHookSetup.install(into: nil, host: host, executablePath: "/usr/bin/other")
      }
    }
  }
}
