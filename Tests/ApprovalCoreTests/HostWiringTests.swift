import Foundation
import Testing

@testable import ApprovalCore

private let stablePath = "/opt/homebrew/bin/countersign"
private let oldPath = "/Users/dev/.local/bin/countersign"

private func entry(_ command: String, timeout: String = "3600", codex: Bool = false) -> String {
  let status = codex ? ",\n          \"statusMessage\": \"Waiting for the approval panel\"" : ""
  return """
    {
      "hooks": {
        "PermissionRequest": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "\(command)",
                "timeout": \(timeout)\(status)
              }
            ]
          }
        ]
      }
    }

    """
}

private func antigravityHook(_ command: String, matcher: String = "*", timeout: String = "3600")
  -> String
{
  """
  {"countersign": {"PreToolUse": [{"matcher": "\(matcher)", "hooks": [{"type": "command", "command": "\(command)", "timeout": \(timeout)}]}]}}
  """
}

private func status(
  _ text: String?, host: ApprovalCore.Host = .claude, directoryExists: Bool = true,
  stable: String = stablePath
) -> HostWiringStatus {
  let file: Doctor.FileState = text.map { .bytes(Array($0.utf8)) } ?? .missing
  return HostWiring.status(
    host: host, directoryExists: directoryExists, file: file, stablePath: stable)
}

@Suite struct HostWiringTests {
  @Test func isNotInstalledWithoutTheHostDirectory() {
    #expect(
      status(entry("\(stablePath) hook --host claude"), directoryExists: false) == .notInstalled)
    #expect(status(nil, directoryExists: false) == .notInstalled)
  }

  @Test func isNotWiredWithoutAnEntryOfOurs() {
    #expect(status(nil) == .notWired)
    #expect(status(" \n") == .notWired)
    #expect(status("{}\n") == .notWired)
    #expect(status(entry("/usr/local/bin/other-tool check")) == .notWired)
  }

  @Test func needsAnUpdateWhenOnlyTheUserPromptSubmitEntryIsStale() {
    let settings = """
      {"hooks": {
        "PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "\(stablePath) hook --host claude", "timeout": 3600}]}],
        "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\(oldPath) hook --host claude"}]}]
      }}
      """
    #expect(
      status(settings) == .needsUpdate(HostWiringUpdate(otherExecutablePaths: [])))
    let current = settings.replacingOccurrences(
      of: "\(oldPath) hook --host claude\"",
      with: "\(stablePath) hook --host claude\", \"async\": true, \"timeout\": 3600")
    #expect(status(current) == .wired)
  }

  @Test func isWiredWhenSetupWouldChangeNothing() {
    #expect(status(entry("\(stablePath) hook --host claude")) == .wired)
    #expect(status(entry("\(stablePath) hook --host codex", codex: true), host: .codex) == .wired)
  }

  @Test func needsAnUpdateWhenTheEntryPointsElsewhere() {
    let update = HostWiringUpdate(otherExecutablePaths: [oldPath])
    #expect(status(entry("\(oldPath) hook --host claude")) == .needsUpdate(update))
  }

  @Test func needsAnUpdateWhenTheEntrysArgumentsDiffer() {
    #expect(
      status(entry("countersign hook --host claude --grace 3"))
        == .needsUpdate(
          HostWiringUpdate(
            otherExecutablePaths: ["countersign"],
            otherArguments: ["hook --host claude --grace 3"])))
    #expect(
      status(entry("\(stablePath) hook --host claude --verbose"))
        == .needsUpdate(
          HostWiringUpdate(
            otherExecutablePaths: [], otherArguments: ["hook --host claude --verbose"])))
    let codex = entry("\(oldPath) hook --host claude", codex: true)
    #expect(
      status(codex, host: .codex)
        == .needsUpdate(
          HostWiringUpdate(
            otherExecutablePaths: [oldPath], otherArguments: ["hook --host claude"])))
  }

  @Test func leavesAQuotedStablePathWired() {
    #expect(status(entry("'\(stablePath)' hook --host claude")) == .wired)
  }

  @Test func needsAnUpdateWhenOnlyTheEntrysFieldsDiffer() {
    #expect(
      status(entry("\(stablePath) hook --host claude", timeout: "600"))
        == .needsUpdate(HostWiringUpdate(otherExecutablePaths: [])))
    #expect(
      status(entry("\(stablePath) hook --host codex"), host: .codex)
        == .needsUpdate(HostWiringUpdate(otherExecutablePaths: [])))
  }

  @Test func namesEachOtherPathAndArgumentsOnce() {
    let twice = """
      {"hooks": {"PermissionRequest": [
        {"matcher": "", "hooks": [{"type": "command", "command": "\(oldPath) hook --host claude x", "timeout": 3600}]},
        {"matcher": "", "hooks": [{"type": "command", "command": "\(oldPath) hook --host claude x", "timeout": 3600}]},
        {"matcher": "", "hooks": [{"type": "command", "command": "\(stablePath) hook --host claude", "timeout": 3600}]}
      ]}}
      """
    #expect(
      status(twice)
        == .needsUpdate(
          HostWiringUpdate(
            otherExecutablePaths: [oldPath], otherArguments: ["hook --host claude x"])))
  }

  @Test func isUnusableWhenSetupWouldFail() {
    #expect(status("{ nope") == .unusable("not valid JSON at line 1, column 3"))
    #expect(status("{\"hooks\": []}") == .unusable("hooks is not an object"))
    #expect(status("[]") == .unusable("the top level is not an object"))
    #expect(
      status("{}", stable: "/usr/local/bin/approve")
        == .unusable(
          "/usr/local/bin/approve is not named countersign, so its entry could not be found again"))
    #expect(
      HostWiring.status(
        host: .claude, directoryExists: true, file: .unreadable("permission denied"),
        stablePath: stablePath) == .unusable("permission denied"))
  }

  @Test func offersOneActionPerStatus() {
    let update = HostWiringStatus.needsUpdate(HostWiringUpdate(otherExecutablePaths: []))
    #expect(HostWiring.action(for: .notWired) == .wire)
    #expect(HostWiring.action(for: update) == .update)
    #expect(HostWiring.action(for: .wired) == .remove)
    #expect(HostWiring.action(for: .notInstalled) == nil)
    #expect(HostWiring.action(for: .unusable("x")) == nil)
    #expect(HostWiringAction.wire.title == "Wire")
    #expect(HostWiringAction.update.title == "Update")
    #expect(HostWiringAction.remove.title == "Remove")
    #expect(HostWiringAction.remove.uninstalls)
    #expect(!HostWiringAction.wire.uninstalls)
    #expect(!HostWiringAction.update.uninstalls)
  }

  @Test func titlesEveryStatus() {
    #expect(HostWiring.title(for: .notInstalled) == "Not installed")
    #expect(HostWiring.title(for: .notWired) == "Not wired")
    #expect(HostWiring.title(for: .wired) == "Wired")
    #expect(
      HostWiring.title(for: .needsUpdate(HostWiringUpdate(otherExecutablePaths: [])))
        == "Needs an update")
    #expect(HostWiring.title(for: .unusable("x")) == "Can't be set up")
  }

  @Test func describesWhatAnUpdateChanges() {
    let both = HostWiringStatus.needsUpdate(
      HostWiringUpdate(
        otherExecutablePaths: [oldPath, "/x/countersign"],
        otherArguments: ["hook --host claude x", "hook"]))
    #expect(
      HostWiring.detail(for: both, host: .claude)
        == "Points at \(oldPath), /x/countersign; runs hook --host claude x, hook rather than hook --host claude"
    )
    let arguments = HostWiringStatus.needsUpdate(
      HostWiringUpdate(otherExecutablePaths: [], otherArguments: ["hook --host claude"]))
    #expect(
      HostWiring.detail(for: arguments, host: .codex)
        == "Runs hook --host claude rather than hook --host codex")
    let fields = HostWiringStatus.needsUpdate(HostWiringUpdate(otherExecutablePaths: []))
    #expect(HostWiring.detail(for: fields, host: .claude) == "Refreshes the entry's timeout")
    #expect(
      HostWiring.detail(for: fields, host: .codex)
        == "Refreshes the entry's timeout and status message")
  }

  @Test func readsCursorsOwnFile() {
    let ours = "{\"command\": \"\(stablePath) hook --host cursor\", \"timeout\": 3600}"
    let wired = """
      {"version": 1, "hooks": {"beforeShellExecution": [\(ours)], "beforeMCPExecution": [\(ours)]}}
      """
    #expect(status(wired, host: .cursor) == .wired)
    #expect(status(nil, host: .cursor) == .notWired)
    #expect(status("{\"version\": 1, \"hooks\": {}}", host: .cursor) == .notWired)
    #expect(status(entry("\(stablePath) hook --host cursor"), host: .cursor) == .notWired)
    #expect(status(wired, host: .cursor, directoryExists: false) == .notInstalled)
    #expect(
      status("{\"hooks\": {\"beforeMCPExecution\": 1}}", host: .cursor)
        == .unusable("hooks.beforeMCPExecution is not an array"))
  }

  @Test func needsAnUpdateWhenACursorEventLacksTheEntry() {
    let old = "{\"command\": \"\(oldPath) hook --host cursor\", \"timeout\": 3600}"
    let text = """
      {"version": 1, "hooks": {"beforeShellExecution": [\(old)]}}
      """
    #expect(
      status(text, host: .cursor)
        == .needsUpdate(
          HostWiringUpdate(
            otherExecutablePaths: [oldPath], missingEvents: ["beforeMCPExecution"])))
  }

  @Test func describesACursorUpdate() {
    let missing = HostWiringStatus.needsUpdate(
      HostWiringUpdate(
        otherExecutablePaths: [], missingEvents: ["beforeShellExecution", "beforeMCPExecution"]))
    #expect(
      HostWiring.detail(for: missing, host: .cursor)
        == "Adds the entry under beforeShellExecution and beforeMCPExecution")
    let fields = HostWiringStatus.needsUpdate(HostWiringUpdate(otherExecutablePaths: []))
    #expect(HostWiring.detail(for: fields, host: .cursor) == "Refreshes the entry's timeout")
    let empty = HostWiringUpdate(otherExecutablePaths: [])
    #expect(empty.otherArguments.isEmpty)
    #expect(empty.missingEvents.isEmpty)
  }

  @Test func readsAntigravitysOwnFile() {
    let wired = antigravityHook("\(stablePath) hook --host antigravity")
    #expect(status(wired, host: .antigravity) == .wired)
    #expect(status(nil, host: .antigravity) == .notWired)
    #expect(status("{\"audit\": {}}", host: .antigravity) == .notWired)
    #expect(status(entry("\(stablePath) hook --host antigravity"), host: .antigravity) == .notWired)
    #expect(status(wired, host: .antigravity, directoryExists: false) == .notInstalled)
    #expect(status("[]", host: .antigravity) == .unusable("the top level is not an object"))
  }

  @Test func isNotWiredWhileOurNamedHookIsInAnotherShape() {
    let misshapen = antigravityHook("\(stablePath) hook --host antigravity", matcher: "run_command")
    #expect(status(misshapen, host: .antigravity) == .notWired)
    #expect(HostWiring.action(for: status(misshapen, host: .antigravity)) == .wire)
  }

  @Test func needsAnUpdateWhenTheAntigravityEntryPointsElsewhere() {
    #expect(
      status(antigravityHook("\(oldPath) hook --host antigravity x"), host: .antigravity)
        == .needsUpdate(
          HostWiringUpdate(
            otherExecutablePaths: [oldPath], otherArguments: ["hook --host antigravity x"])))
    let fields = HostWiringStatus.needsUpdate(HostWiringUpdate(otherExecutablePaths: []))
    #expect(
      status(
        antigravityHook("\(stablePath) hook --host antigravity", timeout: "600"), host: .antigravity
      )
        == fields)
    #expect(HostWiring.detail(for: fields, host: .antigravity) == "Refreshes the entry's timeout")
  }

  @Test func detailsOnlyUpdatesAndProblems() {
    #expect(
      HostWiring.detail(for: .unusable("hooks is not an object"), host: .codex)
        == "hooks is not an object")
    #expect(HostWiring.detail(for: .notInstalled, host: .claude) == nil)
    #expect(HostWiring.detail(for: .notWired, host: .claude) == nil)
    #expect(HostWiring.detail(for: .wired, host: .claude) == nil)
  }
}
