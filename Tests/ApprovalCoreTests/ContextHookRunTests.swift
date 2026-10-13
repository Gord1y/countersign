import Foundation
import Testing

@testable import ApprovalCore

private let brewPath = "/opt/homebrew/bin/countersign"
private let firstMoment = Date(timeIntervalSince1970: 1_790_000_000)
private let secondMoment = Date(timeIntervalSince1970: 1_790_000_100)

private let permissionOnly = """
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

private struct Sandbox {
  let directory: URL
  let file: URL

  init(contents: String?, fileName: String = "settings.json") throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-context-hook-run-\(UUID().uuidString)")
      .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    file = directory.appendingPathComponent(fileName)
    if let contents {
      try Data(contents.utf8).write(to: file)
    }
  }

  func location(_ host: ApprovalCore.Host = .claude) -> HookConfigLocation {
    HookConfigLocation(host: host, directory: directory, file: file)
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }

  var text: String? {
    (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) }
  }

  var names: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
  }
}

@Suite struct ContextHookRunTests {
  @Test func previewsTheDiffForEnablingIntoAFileWithoutTheEntry() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    let preview = ContextHookRun.preview(
      locations: [sandbox.location()], executablePath: brewPath, enable: true)
    #expect(preview.failures.isEmpty)
    #expect(preview.hasChanges)
    #expect(preview.changedFiles == [sandbox.file])
    #expect(preview.text.hasPrefix(sandbox.file.path + "\n"))
    #expect(preview.text.contains("+    \"UserPromptSubmit\": ["))
    #expect(preview.text.contains("\"async\": true"))
    #expect(sandbox.text == permissionOnly)
  }

  @Test func previewsAMissingFileAsANewOne() throws {
    let sandbox = try Sandbox(contents: nil)
    defer { sandbox.remove() }
    let preview = ContextHookRun.preview(
      locations: [sandbox.location()], executablePath: brewPath, enable: true)
    #expect(preview.hasChanges)
    #expect(preview.text.contains("--- /dev/null"))
    #expect(sandbox.names.isEmpty)
  }

  @Test func previewsNothingToDoWhenTheFileAlreadyMatches() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    let preview = ContextHookRun.preview(
      locations: [sandbox.location()], executablePath: brewPath, enable: false)
    #expect(!preview.hasChanges)
    #expect(preview.failures.isEmpty)
    #expect(preview.text == "\(sandbox.file.path): already up to date\n")
  }

  @Test func previewReportsAFileThatIsNotJSON() throws {
    let sandbox = try Sandbox(contents: "not json")
    defer { sandbox.remove() }
    let preview = ContextHookRun.preview(
      locations: [sandbox.location()], executablePath: brewPath, enable: true)
    #expect(preview.failures.count == 1)
    #expect(preview.failures[0].hasPrefix("\(sandbox.file.path): error: "))
    #expect(!preview.hasChanges)
  }

  @Test func enablingThenDisablingRestoresTheOriginalBytesWithOneBackupPerWrite() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.apply(
        locations: [sandbox.location()], executablePath: brewPath, enable: true, now: firstMoment
      ).isEmpty)
    let enabled = try #require(sandbox.text)
    #expect(enabled != permissionOnly)
    #expect(!ContextHookSetup.entries(in: Array(enabled.utf8)).isEmpty)
    #expect(sandbox.names.count == 2)
    #expect(
      ContextHookRun.apply(
        locations: [sandbox.location()], executablePath: brewPath, enable: false, now: secondMoment
      ).isEmpty)
    #expect(sandbox.text == permissionOnly)
    #expect(sandbox.names.count == 3)
  }

  @Test func enablingTwiceWritesNothingTheSecondTime() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.apply(
        locations: [sandbox.location()], executablePath: brewPath, enable: true, now: firstMoment
      ).isEmpty)
    let names = sandbox.names
    #expect(
      ContextHookRun.apply(
        locations: [sandbox.location()], executablePath: brewPath, enable: true, now: secondMoment
      ).isEmpty)
    #expect(sandbox.names == names)
  }

  @Test func createsAMissingFileWhenEnabling() throws {
    let sandbox = try Sandbox(contents: nil)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.apply(
        locations: [sandbox.location()], executablePath: brewPath, enable: true, now: firstMoment
      ).isEmpty)
    let written = try #require(sandbox.text)
    #expect(ContextHookSetup.entries(in: Array(written.utf8)).count == 2)
    #expect(sandbox.names == ["settings.json"])
  }

  @Test func applyingToInvalidJSONReturnsTheErrorLineAndWritesNothing() throws {
    let sandbox = try Sandbox(contents: "{ nope")
    defer { sandbox.remove() }
    let line = ContextHookRun.apply(
      locations: [sandbox.location()], executablePath: brewPath, enable: true, now: firstMoment)
    #expect(line.first?.hasPrefix("\(sandbox.file.path): error: ") == true)
    #expect(sandbox.text == "{ nope")
    #expect(sandbox.names == ["settings.json"])
  }

  @Test func reportsTheHookStatusOfAFile() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.status(location: sandbox.location(), executablePath: brewPath) == .notWired)
    _ = ContextHookRun.apply(
      locations: [sandbox.location()], executablePath: brewPath, enable: true, now: firstMoment)
    #expect(ContextHookRun.status(location: sandbox.location(), executablePath: brewPath) == .wired)
    let stale = try #require(sandbox.text).replacingOccurrences(
      of: "\"async\": true,", with: "\"async\": false,")
    try Data(stale.utf8).write(to: sandbox.file)
    #expect(
      ContextHookRun.status(location: sandbox.location(), executablePath: brewPath) == .needsUpdate)
    let both = try #require(sandbox.text)
    let promptOnly = try #require(
      try HookSetup.removeEntries(
        from: Array(both.utf8), event: ContextHookSetup.toolEventName))
    try Data(promptOnly).write(to: sandbox.file)
    #expect(
      ContextHookRun.status(location: sandbox.location(), executablePath: brewPath) == .needsUpdate)
    try Data("{ nope".utf8).write(to: sandbox.file)
    guard
      case .unusable(let reason) = ContextHookRun.status(
        location: sandbox.location(), executablePath: brewPath)
    else {
      Issue.record("expected unusable")
      return
    }
    #expect(!reason.isEmpty)
    #expect(ContextHookStatus.wired.title == "Wired")
    #expect(ContextHookStatus.notWired.title == "Not wired")
    #expect(ContextHookStatus.needsUpdate.title == "Needs an update")
    #expect(ContextHookStatus.unusable("x").title == "Can't be set up")
  }

  @Test func reportsAMissingFileAsNotWired() throws {
    let sandbox = try Sandbox(contents: nil)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.status(location: sandbox.location(), executablePath: brewPath) == .notWired)
  }

  @Test func previewsBothDiffsForAClaudeFileAndACodexFile() throws {
    let claude = try Sandbox(contents: permissionOnly)
    let codex = try Sandbox(contents: nil, fileName: "hooks.json")
    defer {
      claude.remove()
      codex.remove()
    }
    let preview = ContextHookRun.preview(
      locations: [claude.location(), codex.location(.codex)], executablePath: brewPath,
      enable: true)
    #expect(preview.failures.isEmpty)
    #expect(preview.changedFiles == [claude.file, codex.file])
    #expect(preview.text.contains(claude.file.path + "\n"))
    #expect(preview.text.contains("--- /dev/null"))
    #expect(preview.text.contains(codex.file.path))
  }

  @Test func enablingWritesCodexEntriesSynchronouslyAndRecordsBothTrustRecords() throws {
    let claude = try Sandbox(contents: permissionOnly)
    let codex = try Sandbox(contents: nil, fileName: "hooks.json")
    defer {
      claude.remove()
      codex.remove()
    }
    let promptRecord = codex.directory.appendingPathComponent("prompt-trust.json")
    let toolRecord = codex.directory.appendingPathComponent("tool-trust.json")
    let failures = ContextHookRun.apply(
      locations: [claude.location(), codex.location(.codex)], executablePath: brewPath,
      enable: true, now: firstMoment, codexPromptTrustFile: promptRecord,
      codexToolTrustFile: toolRecord)
    #expect(failures.isEmpty)
    let claudeEntries = ContextHookSetup.entries(in: Array(try #require(claude.text).utf8))
    let codexEntries = ContextHookSetup.entries(in: Array(try #require(codex.text).utf8))
    #expect(claudeEntries.count == 2)
    #expect(codexEntries.count == 2)
    #expect(codexEntries.allSatisfy { !$0.isAsync })
    #expect(FileManager.default.fileExists(atPath: promptRecord.path))
    #expect(FileManager.default.fileExists(atPath: toolRecord.path))
  }

  @Test func disablingRemovesBothHostsEntries() throws {
    let claude = try Sandbox(contents: permissionOnly)
    let codex = try Sandbox(contents: nil, fileName: "hooks.json")
    defer {
      claude.remove()
      codex.remove()
    }
    let locations = [claude.location(), codex.location(.codex)]
    _ = ContextHookRun.apply(
      locations: locations, executablePath: brewPath, enable: true, now: firstMoment)
    let failures = ContextHookRun.apply(
      locations: locations, executablePath: brewPath, enable: false, now: secondMoment)
    #expect(failures.isEmpty)
    #expect(ContextHookSetup.entries(in: Array(try #require(claude.text).utf8)).isEmpty)
    #expect(ContextHookSetup.entries(in: Array(try #require(codex.text).utf8)).isEmpty)
  }

  @Test func reportsACodexFileWithOnlyThePermissionEntryAsNotWired() throws {
    let codex = try Sandbox(
      contents: permissionOnly.replacingOccurrences(of: "--host claude", with: "--host codex"),
      fileName: "hooks.json")
    defer { codex.remove() }
    #expect(
      ContextHookRun.status(location: codex.location(.codex), executablePath: brewPath)
        == .notWired)
    _ = ContextHookRun.apply(
      locations: [codex.location(.codex)], executablePath: brewPath, enable: true,
      now: firstMoment)
    #expect(
      ContextHookRun.status(location: codex.location(.codex), executablePath: brewPath)
        == .wired)
  }

  @Test func refusesAnExecutableThatIsNotCountersign() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    let line = ContextHookRun.apply(
      locations: [sandbox.location()], executablePath: "", enable: true, now: firstMoment)
    #expect(line.first?.hasPrefix("\(sandbox.file.path): error: ") == true)
    #expect(sandbox.text == permissionOnly)
  }
}

private let demoSettings = """
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

@Suite struct ContextHookStatusAgreementTests {
  @Test func contextAndAgentsStatusesAgreeOnTheDemoSettings() throws {
    let sandbox = try Sandbox(contents: demoSettings)
    defer { sandbox.remove() }
    let context = ContextHookRun.status(location: sandbox.location(), executablePath: brewPath)
    let agents = HostWiring.status(
      host: .claude, directoryExists: true,
      file: ConfigFileStore.fileState(sandbox.file), stablePath: brewPath,
      addsWaitingEntry: true, addsContextEntry: true)
    #expect(context == .wired)
    #expect(agents == .wired)
  }

  @Test func contextAndAgentsStatusesAgreeWhenTheFileHoldsAnotherPath() throws {
    let other = demoSettings.replacingOccurrences(
      of: "/opt/homebrew/bin/countersign", with: "/opt/other/bin/countersign")
    let sandbox = try Sandbox(contents: other)
    defer { sandbox.remove() }
    let context = ContextHookRun.status(location: sandbox.location(), executablePath: brewPath)
    let agents = HostWiring.status(
      host: .claude, directoryExists: true,
      file: ConfigFileStore.fileState(sandbox.file), stablePath: brewPath,
      addsWaitingEntry: true, addsContextEntry: true)
    #expect(context == .needsUpdate)
    #expect(agents != .wired)
  }
}
