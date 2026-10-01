import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"
private let oldPath = "/Users/dev/.local/bin/countersign"
private let moment = Date(timeIntervalSince1970: 1_790_000_000)

private struct Outcome {
  let succeeded: Bool
  let output: String
  let asked: [String]

  var lines: [String] {
    output.components(separatedBy: "\n")
  }
}

private struct Sandbox {
  let home: URL
  let claude: HookConfigLocation
  let codex: HookConfigLocation
  let cursor: HookConfigLocation
  let antigravity: HookConfigLocation
  let config: URL
  let codexHookTrustFile: URL

  init() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-setup-run-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    home = root.resolvingSymlinksInPath()
    claude = HookConfigLocation.location(for: .claude, environment: [:], home: home)
    codex = HookConfigLocation.location(for: .codex, environment: [:], home: home)
    cursor = HookConfigLocation.location(for: .cursor, environment: [:], home: home)
    antigravity = HookConfigLocation.location(for: .antigravity, environment: [:], home: home)
    config = AppPaths(home: home).configFile
    codexHookTrustFile = AppPaths(home: home).codexHookTrustFile
    for directory in [claude.directory, codex.directory, cursor.directory] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
  }

  func remove() {
    try? FileManager.default.removeItem(at: home)
  }

  func put(_ text: String, at file: URL) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  func text(of file: URL) -> String? {
    (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) }
  }

  func names(in directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
  }

  func run(
    _ locations: [HookConfigLocation], uninstall: Bool = false, addsWaitingEntry: Bool = false,
    codexHookTrustFile: URL? = nil,
    answer: @escaping (String) -> Bool = { _ in true }
  ) -> Outcome {
    var output = ""
    var asked: [String] = []
    var setup = SetupRun(
      executablePath: brewPath, uninstall: uninstall, addsWaitingEntry: addsWaitingEntry,
      codexHookTrustFile: codexHookTrustFile,
      now: { moment },
      output: { output += $0 },
      confirm: { path in
        asked.append(path)
        return answer(path)
      })
    var succeeded = true
    for location in locations {
      succeeded = setup.apply(location) && succeeded
    }
    return Outcome(succeeded: succeeded, output: output, asked: asked)
  }
}

private func claudeEntry(_ command: String) -> String {
  """
  {
    "hooks": {
      "PermissionRequest": [
        {
          "matcher": "",
          "hooks": [
            {
              "type": "command",
              "command": "\(command)",
              "timeout": 3600
            }
          ]
        }
      ]
    }
  }

  """
}

private func codexEntry(_ command: String) -> String {
  """
  {
    "hooks": {
      "PermissionRequest": [
        {
          "matcher": "",
          "hooks": [
            {
              "type": "command",
              "command": "\(command)",
              "timeout": 3600,
              "statusMessage": "Waiting for the approval panel"
            }
          ]
        }
      ]
    }
  }

  """
}

private let claudeOld = claudeEntry("\(oldPath) hook --host claude --verbose")
private let claudeInstalled = claudeEntry("\(brewPath) hook --host claude")
private let codexOld = codexEntry("\(oldPath) hook --host codex")
private let codexInstalled = codexEntry("\(brewPath) hook --host codex")

@Suite struct SetupRunTests {
  @Test func rewritesAnOldEntryWithoutTouchingTheConfigFile() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(claudeOld, at: sandbox.claude.file)
    let outcome = sandbox.run([sandbox.claude])
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.claude.file.path])
    #expect(sandbox.text(of: sandbox.claude.file) == claudeInstalled)
    #expect(
      outcome.lines.filter { $0.hasSuffix(": updated") } == ["\(sandbox.claude.file.path): updated"]
    )
    #expect(outcome.lines.contains("+++ \(sandbox.claude.file.path)"))
    #expect(outcome.lines.contains { $0.hasPrefix("\(sandbox.claude.file.path): backup at ") })
    #expect(sandbox.text(of: sandbox.config) == nil)
  }

  @Test func changesNothingWhenNothingIsConfirmed() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(claudeOld, at: sandbox.claude.file)
    let outcome = sandbox.run([sandbox.claude]) { _ in false }
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.claude.file.path])
    #expect(sandbox.text(of: sandbox.claude.file) == claudeOld)
  }

  @Test func staysAlreadyUpToDate() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(claudeInstalled, at: sandbox.claude.file)
    let outcome = sandbox.run([sandbox.claude])
    #expect(outcome.succeeded)
    #expect(outcome.asked == [])
    #expect(outcome.output == "\(sandbox.claude.file.path): already up to date\n")
  }

  @Test func updatesBothHostsWhateverTheConfigHoldsAndThenChangesNothing() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put("{ nope", at: sandbox.config)
    try sandbox.put(claudeOld, at: sandbox.claude.file)
    try sandbox.put(codexOld, at: sandbox.codex.file)
    let first = sandbox.run([sandbox.claude, sandbox.codex])
    #expect(first.succeeded)
    #expect(first.asked == [sandbox.claude.file.path, sandbox.codex.file.path])
    #expect(sandbox.text(of: sandbox.claude.file) == claudeInstalled)
    #expect(sandbox.text(of: sandbox.codex.file) == codexInstalled)
    #expect(sandbox.text(of: sandbox.config) == "{ nope")
    let second = sandbox.run([sandbox.claude, sandbox.codex])
    #expect(second.succeeded)
    #expect(second.asked == [])
    #expect(
      second.output
        == "\(sandbox.claude.file.path): already up to date\n\(sandbox.codex.file.path): already up to date\n"
    )
  }

  @Test func createsCodexsFile() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let outcome = sandbox.run([sandbox.codex])
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.codex.file.path])
    #expect(sandbox.text(of: sandbox.codex.file) == codexInstalled)
    #expect(sandbox.text(of: sandbox.config) == nil)
    #expect(outcome.lines.contains("--- /dev/null"))
  }

  @Test func installingCodexWritesAFreshTrustRecord() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexOld, at: sandbox.codex.file)
    try CodexHookTrustRecordStore.save(
      CodexHookTrustRecord(hookKey: "stale", command: "stale", markedDone: true),
      to: sandbox.codexHookTrustFile)
    let key = "\(sandbox.codex.file.path):permission_request:0:0"
    try sandbox.put(
      "model = \"o3\"\n\n[hooks.state.\"\(key)\"]\ntrusted_hash = \"sha256:old\"\n",
      at: CodexHookTrust.configFile(for: sandbox.codex))
    let outcome = sandbox.run([sandbox.codex], codexHookTrustFile: sandbox.codexHookTrustFile)
    #expect(outcome.succeeded)
    #expect(
      CodexHookTrustRecordStore.load(file: sandbox.codexHookTrustFile)
        == CodexHookTrustRecord(
          hookKey: key, command: "\(brewPath) hook --host codex",
          hashAtWrite: .stored("sha256:old")))
  }

  @Test func installingCodexWithoutItsConfigRecordsNoHashAtWrite() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let outcome = sandbox.run([sandbox.codex], codexHookTrustFile: sandbox.codexHookTrustFile)
    #expect(outcome.succeeded)
    #expect(
      CodexHookTrustRecordStore.load(file: sandbox.codexHookTrustFile)
        == CodexHookTrustRecord(
          hookKey: "\(sandbox.codex.file.path):permission_request:0:0",
          command: "\(brewPath) hook --host codex", hashAtWrite: .absent))
  }

  @Test func installingCodexWithAnUnreadableConfigRecordsThatItCouldNotRead() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexOld, at: sandbox.codex.file)
    try CodexHookTrustRecordStore.save(
      CodexHookTrustRecord(hookKey: "stale", command: "stale", markedDone: true),
      to: sandbox.codexHookTrustFile)
    try sandbox.put("[hooks]\nstate = {}\n", at: CodexHookTrust.configFile(for: sandbox.codex))
    let outcome = sandbox.run([sandbox.codex], codexHookTrustFile: sandbox.codexHookTrustFile)
    #expect(outcome.succeeded)
    #expect(
      CodexHookTrustRecordStore.load(file: sandbox.codexHookTrustFile)
        == CodexHookTrustRecord(
          hookKey: "\(sandbox.codex.file.path):permission_request:0:0",
          command: "\(brewPath) hook --host codex", hashAtWrite: .unread))
  }

  @Test func installingCodexDeletesTheRecordItCannotSave() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let blocked = sandbox.home.appendingPathComponent("blocked")
    try sandbox.put("a file, not a directory", at: blocked)
    let outcome = sandbox.run(
      [sandbox.codex], codexHookTrustFile: blocked.appendingPathComponent("codex-hook-trust.json"))
    #expect(outcome.succeeded)
    #expect(sandbox.text(of: blocked) == "a file, not a directory")
  }

  @Test func installingWithNoTrustFileConfiguredNeverThrows() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexOld, at: sandbox.codex.file)
    let outcome = sandbox.run([sandbox.codex])
    #expect(outcome.succeeded)
  }

  @Test func installingAnotherHostNeverTouchesTheCodexTrustRecord() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(claudeOld, at: sandbox.claude.file)
    try CodexHookTrustRecordStore.save(
      CodexHookTrustRecord(hookKey: "kept", command: "kept"), to: sandbox.codexHookTrustFile)
    let outcome = sandbox.run([sandbox.claude], codexHookTrustFile: sandbox.codexHookTrustFile)
    #expect(outcome.succeeded)
    #expect(
      CodexHookTrustRecordStore.load(file: sandbox.codexHookTrustFile)
        == CodexHookTrustRecord(hookKey: "kept", command: "kept"))
  }

  @Test func alreadyUpToDateNeverDeletesTheCodexTrustRecord() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexInstalled, at: sandbox.codex.file)
    try CodexHookTrustRecordStore.save(
      CodexHookTrustRecord(hookKey: "kept", command: "kept"), to: sandbox.codexHookTrustFile)
    let outcome = sandbox.run([sandbox.codex], codexHookTrustFile: sandbox.codexHookTrustFile)
    #expect(outcome.succeeded)
    #expect(
      CodexHookTrustRecordStore.load(file: sandbox.codexHookTrustFile)
        == CodexHookTrustRecord(hookKey: "kept", command: "kept"))
  }

  @Test func previewNeverDeletesTheCodexTrustRecord() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexOld, at: sandbox.codex.file)
    try CodexHookTrustRecordStore.save(
      CodexHookTrustRecord(hookKey: "kept", command: "kept"), to: sandbox.codexHookTrustFile)
    var preview = SetupRun(
      executablePath: brewPath, uninstall: false, addsWaitingEntry: false, writesFiles: false,
      codexHookTrustFile: sandbox.codexHookTrustFile, output: { _ in }, confirm: { _ in true })
    _ = preview.apply(sandbox.codex)
    #expect(
      CodexHookTrustRecordStore.load(file: sandbox.codexHookTrustFile)
        == CodexHookTrustRecord(hookKey: "kept", command: "kept"))
  }

  @Test func stampsTheBackupWithTheCurrentTimeByDefault() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put("{}\n", at: sandbox.codex.file)
    let before = Date()
    var setup = SetupRun(
      executablePath: brewPath, uninstall: false, addsWaitingEntry: false, output: { _ in },
      confirm: { _ in true })
    let succeeded = setup.apply(sandbox.codex)
    #expect(succeeded)
    let stamps = [before, Date()].map {
      ConfigFileStore.backupName(for: "hooks.json", date: $0)
    }
    #expect(sandbox.names(in: sandbox.codex.directory).contains { stamps.contains($0) })
    #expect(sandbox.text(of: sandbox.codex.file) == codexInstalled)
  }

  @Test func uninstallsTheCodexHooksEntry() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexOld, at: sandbox.codex.file)
    let outcome = sandbox.run([sandbox.codex], uninstall: true)
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.codex.file.path])
    #expect(sandbox.text(of: sandbox.codex.file) == "{\n  \"hooks\": {}\n}\n")
    #expect(sandbox.text(of: sandbox.config) == nil)
    let again = sandbox.run([sandbox.codex], uninstall: true)
    #expect(again.output == "\(sandbox.codex.file.path): already up to date\n")
  }

  @Test func uninstallingCodexDeletesTheTrustRecord() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexOld, at: sandbox.codex.file)
    try CodexHookTrustRecordStore.save(
      CodexHookTrustRecord(hookKey: "stale", command: "stale"), to: sandbox.codexHookTrustFile)
    let outcome = sandbox.run(
      [sandbox.codex], uninstall: true, codexHookTrustFile: sandbox.codexHookTrustFile)
    #expect(outcome.succeeded)
    #expect(CodexHookTrustRecordStore.load(file: sandbox.codexHookTrustFile) == nil)
  }

  @Test func addsTheStopEntryNextToThePermissionEntryWhileNoticesAreOn() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(claudeInstalled, at: sandbox.claude.file)
    let outcome = sandbox.run([sandbox.claude], addsWaitingEntry: true)
    #expect(outcome.succeeded)
    let written = try #require(sandbox.text(of: sandbox.claude.file))
    #expect(written.contains("\"PermissionRequest\""))
    #expect(written.contains("\(brewPath) hook --host claude --event waiting"))
    #expect(outcome.output.contains("\"Stop\""))
  }

  @Test func leavesAnExistingStopEntryAloneWhileNoticesAreOff() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let withStop = try WaitingHookSetup.install(
      into: Array(claudeInstalled.utf8), host: .claude, executablePath: brewPath)
    try sandbox.put(String(decoding: withStop, as: UTF8.self), at: sandbox.claude.file)
    let outcome = sandbox.run([sandbox.claude], addsWaitingEntry: false)
    #expect(outcome.succeeded)
    #expect(outcome.output == "\(sandbox.claude.file.path): already up to date\n")
    #expect(sandbox.text(of: sandbox.claude.file) == String(decoding: withStop, as: UTF8.self))
  }

  @Test func reportsAHookFileThatIsNotJSON() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put("{\"hooks\": ", at: sandbox.claude.file)
    let outcome = sandbox.run([sandbox.claude])
    #expect(!outcome.succeeded)
    #expect(outcome.asked == [])
    #expect(outcome.output.hasPrefix("\(sandbox.claude.file.path): error: not valid JSON"))
  }

  @Test func reportsAHookFileThatCannotBeWritten() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(claudeOld, at: sandbox.claude.file)
    let taken = ConfigFileStore.backupName(for: "settings.json", date: moment)
    try sandbox.put("earlier", at: sandbox.claude.directory.appendingPathComponent(taken))
    let outcome = sandbox.run([sandbox.claude])
    #expect(!outcome.succeeded)
    #expect(sandbox.text(of: sandbox.claude.file) == claudeOld)
    let errorLine = "\(sandbox.claude.file.path): error: "
    #expect(outcome.lines.suffix(2).first?.hasPrefix(errorLine) == true)
    #expect(outcome.lines.last == "")
  }

  @Test func previewsTheDiffAsIfTheQuestionWereAnsweredYes() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(claudeOld, at: sandbox.claude.file)
    let preview = SetupRun.preview(
      sandbox.claude, executablePath: brewPath, uninstall: false, addsWaitingEntry: false)
    let hookPath = sandbox.claude.file.path
    let expected =
      "\(hookPath)\n"
      + UnifiedDiff.render(
        old: claudeOld, new: claudeInstalled, oldLabel: hookPath, newLabel: hookPath)
    #expect(preview.text == expected)
    #expect(preview.changedFiles == [sandbox.claude.file])
    #expect(preview.failures == [])
    #expect(preview.hasChanges)
    #expect(sandbox.text(of: sandbox.claude.file) == claudeOld)
  }

  @Test func previewsNothingForAnUpToDateFile() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexInstalled, at: sandbox.codex.file)
    let preview = SetupRun.preview(
      sandbox.codex, executablePath: brewPath, uninstall: false, addsWaitingEntry: false)
    #expect(preview.text == "\(sandbox.codex.file.path): already up to date\n")
    #expect(!preview.hasChanges)
    let fresh = try Sandbox()
    defer { fresh.remove() }
    let wiring = SetupRun.preview(
      fresh.codex, executablePath: brewPath, uninstall: false, addsWaitingEntry: false)
    #expect(wiring.changedFiles == [fresh.codex.file])
    #expect(fresh.text(of: fresh.codex.file) == nil)
  }

  @Test func previewsARemoval() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(codexInstalled, at: sandbox.codex.file)
    let preview = SetupRun.preview(
      sandbox.codex, executablePath: "", uninstall: true, addsWaitingEntry: false)
    #expect(preview.changedFiles == [sandbox.codex.file])
    #expect(
      preview.text.components(separatedBy: "\n").contains {
        $0.hasPrefix("-") && $0.contains("\"command\": \"\(brewPath) hook --host codex\"")
      })
    #expect(sandbox.text(of: sandbox.codex.file) == codexInstalled)
  }

  @Test func recordsFailuresAndChangedFiles() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put("{ nope", at: sandbox.claude.file)
    let preview = SetupRun.preview(
      sandbox.claude, executablePath: brewPath, uninstall: false, addsWaitingEntry: false)
    #expect(
      preview.failures == [
        "\(sandbox.claude.file.path): error: not valid JSON at line 1, column 3"
      ])
    #expect(!preview.hasChanges)
    var setup = SetupRun(
      executablePath: brewPath, uninstall: false, addsWaitingEntry: false, now: { moment },
      output: { _ in }, confirm: { _ in true })
    let wired = setup.apply(sandbox.codex)
    #expect(wired)
    #expect(setup.changedFiles == [sandbox.codex.file])
    #expect(setup.failures == [])
  }

  @Test func wiresCursorBesideOtherHooksAndUninstallsBackToTheOriginal() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let original = """
      {
        "version": 1,
        "hooks": {
          "afterFileEdit": [
            {
              "command": "./hooks/format.sh"
            }
          ]
        }
      }

      """
    try sandbox.put(original, at: sandbox.cursor.file)
    let outcome = sandbox.run([sandbox.cursor])
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.cursor.file.path])
    #expect(outcome.lines.contains { $0.hasPrefix("\(sandbox.cursor.file.path): backup at ") })
    #expect(sandbox.text(of: sandbox.config) == nil)
    let installed = sandbox.text(of: sandbox.cursor.file) ?? ""
    #expect(installed.contains("\"afterFileEdit\""))
    #expect(
      CursorHookSetup.sites(in: try JSONSpanReader.parse(Array(installed.utf8))).map(\.eventName)
        == ["beforeShellExecution", "beforeMCPExecution"])
    let again = sandbox.run([sandbox.cursor])
    #expect(again.output == "\(sandbox.cursor.file.path): already up to date\n")
    var removal = SetupRun(
      executablePath: "", uninstall: true, addsWaitingEntry: false,
      now: { moment.addingTimeInterval(1) }, output: { _ in }, confirm: { _ in true })
    let removed = removal.apply(sandbox.cursor)
    #expect(removed)
    #expect(sandbox.text(of: sandbox.cursor.file) == original)
  }

  @Test func createsCursorsFileWhenItIsMissing() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let outcome = sandbox.run([sandbox.cursor])
    #expect(outcome.succeeded)
    #expect(outcome.lines.contains("--- /dev/null"))
    let created = sandbox.text(of: sandbox.cursor.file) ?? ""
    #expect(created.hasPrefix("{\n  \"version\": 1,\n  \"hooks\": {\n"))
    #expect(created.contains("\"command\": \"\(brewPath) hook --host cursor\""))
  }

  @Test func rewritesCursorsOldEntriesUnderBothEvents() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let entry = "{\"command\": \"\(oldPath) hook --host cursor --verbose\", \"timeout\": 3600}"
    try sandbox.put(
      "{\"version\": 1, \"hooks\": {\"beforeShellExecution\": [\(entry)], \"beforeMCPExecution\": [\(entry)]}}\n",
      at: sandbox.cursor.file)
    let outcome = sandbox.run([sandbox.cursor])
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.cursor.file.path])
    #expect(sandbox.text(of: sandbox.config) == nil)
    let installed = sandbox.text(of: sandbox.cursor.file) ?? ""
    #expect(!installed.contains("--verbose"))
    #expect(installed.components(separatedBy: "\(brewPath) hook --host cursor").count == 3)
  }

  @Test func createsAntigravitysConfigDirectoryAndFile() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try FileManager.default.createDirectory(
      at: sandbox.antigravity.hostDirectories[0], withIntermediateDirectories: true)
    #expect(sandbox.text(of: sandbox.antigravity.file) == nil)
    let outcome = sandbox.run([sandbox.antigravity])
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.antigravity.file.path])
    #expect(outcome.lines.contains("--- /dev/null"))
    #expect(!outcome.lines.contains { $0.contains("backup at") })
    let created = sandbox.text(of: sandbox.antigravity.file) ?? ""
    #expect(created.hasPrefix("{\n  \"countersign\": {\n    \"PreToolUse\": [\n"))
    #expect(created.contains("\"command\": \"\(brewPath) hook --host antigravity\""))
    let again = sandbox.run([sandbox.antigravity])
    #expect(again.output == "\(sandbox.antigravity.file.path): already up to date\n")
  }

  @Test func wiresAntigravityBesideOtherNamedHooksAndUninstallsBackToTheOriginal() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let original = """
      {
        "audit": {
          "PreToolUse": [
            {
              "matcher": "run_command",
              "hooks": [
                {
                  "type": "command",
                  "command": "~/.gemini/hooks/audit.sh"
                }
              ]
            }
          ]
        }
      }

      """
    try sandbox.put(original, at: sandbox.antigravity.file)
    let outcome = sandbox.run([sandbox.antigravity])
    #expect(outcome.succeeded)
    #expect(
      outcome.lines.contains { $0.hasPrefix("\(sandbox.antigravity.file.path): backup at ") })
    let installed = sandbox.text(of: sandbox.antigravity.file) ?? ""
    #expect(installed.hasPrefix(String(original.dropLast(3))))
    #expect(
      AntigravityHookSetup.hookNodes(in: try JSONSpanReader.parse(Array(installed.utf8))).count
        == 1)
    var removal = SetupRun(
      executablePath: "", uninstall: true, addsWaitingEntry: false,
      now: { moment.addingTimeInterval(1) }, output: { _ in }, confirm: { _ in true })
    let removed = removal.apply(sandbox.antigravity)
    #expect(removed)
    #expect(sandbox.text(of: sandbox.antigravity.file) == original)
  }

  @Test func uninstallNeverCreatesAntigravitysFile() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    let outcome = sandbox.run([sandbox.antigravity], uninstall: true)
    #expect(outcome.succeeded)
    #expect(outcome.output == "\(sandbox.antigravity.file.path): already up to date\n")
    #expect(!FileManager.default.fileExists(atPath: sandbox.antigravity.directory.path))
  }

  @Test func rewritesAntigravitysOldEntry() throws {
    let sandbox = try Sandbox()
    defer { sandbox.remove() }
    try sandbox.put(
      "{\"countersign\": {\"PreToolUse\": [{\"matcher\": \"*\", \"hooks\": [{\"type\": \"command\", \"command\": \"\(oldPath) hook --host antigravity --verbose\", \"timeout\": 3600}]}]}}\n",
      at: sandbox.antigravity.file)
    let outcome = sandbox.run([sandbox.antigravity])
    #expect(outcome.succeeded)
    #expect(outcome.asked == [sandbox.antigravity.file.path])
    #expect(sandbox.text(of: sandbox.config) == nil)
    let installed = sandbox.text(of: sandbox.antigravity.file) ?? ""
    #expect(!installed.contains("--verbose"))
    #expect(installed.contains("\"command\": \"\(brewPath) hook --host antigravity\""))
  }

  @Test func describesErrorsOnOneLine() {
    #expect(
      SetupRun.describe(JSONSpanError(line: 2, column: 5)) == "not valid JSON at line 2, column 5")
    #expect(
      SetupRun.describe(HookSetupError.unexpectedType(key: "hosts", expected: "an object"))
        == "hosts is not an object")
    #expect(
      SetupRun.describe(CocoaError(.fileReadNoPermission))
        == CocoaError(.fileReadNoPermission).localizedDescription)
    #expect(!SetupRun.describe(POSIXError(.ENOTDIR)).contains("\n"))
  }
}
