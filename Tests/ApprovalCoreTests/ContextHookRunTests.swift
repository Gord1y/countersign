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

  init(contents: String?) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-context-hook-run-\(UUID().uuidString)")
      .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    file = directory.appendingPathComponent("settings.json")
    if let contents {
      try Data(contents.utf8).write(to: file)
    }
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
      file: sandbox.file, executablePath: brewPath, enable: true)
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
      file: sandbox.file, executablePath: brewPath, enable: true)
    #expect(preview.hasChanges)
    #expect(preview.text.contains("--- /dev/null"))
    #expect(sandbox.names.isEmpty)
  }

  @Test func previewsNothingToDoWhenTheFileAlreadyMatches() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    let preview = ContextHookRun.preview(
      file: sandbox.file, executablePath: brewPath, enable: false)
    #expect(!preview.hasChanges)
    #expect(preview.failures.isEmpty)
    #expect(preview.text == "\(sandbox.file.path): already up to date\n")
  }

  @Test func previewReportsAFileThatIsNotJSON() throws {
    let sandbox = try Sandbox(contents: "not json")
    defer { sandbox.remove() }
    let preview = ContextHookRun.preview(
      file: sandbox.file, executablePath: brewPath, enable: true)
    #expect(preview.failures.count == 1)
    #expect(preview.failures[0].hasPrefix("\(sandbox.file.path): error: "))
    #expect(!preview.hasChanges)
  }

  @Test func enablingThenDisablingRestoresTheOriginalBytesWithOneBackupPerWrite() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.apply(
        file: sandbox.file, executablePath: brewPath, enable: true, now: firstMoment) == nil)
    let enabled = try #require(sandbox.text)
    #expect(enabled != permissionOnly)
    #expect(!ContextHookSetup.entries(in: Array(enabled.utf8)).isEmpty)
    #expect(sandbox.names.count == 2)
    #expect(
      ContextHookRun.apply(
        file: sandbox.file, executablePath: brewPath, enable: false, now: secondMoment) == nil)
    #expect(sandbox.text == permissionOnly)
    #expect(sandbox.names.count == 3)
  }

  @Test func enablingTwiceWritesNothingTheSecondTime() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.apply(
        file: sandbox.file, executablePath: brewPath, enable: true, now: firstMoment) == nil)
    let names = sandbox.names
    #expect(
      ContextHookRun.apply(
        file: sandbox.file, executablePath: brewPath, enable: true, now: secondMoment) == nil)
    #expect(sandbox.names == names)
  }

  @Test func createsAMissingFileWhenEnabling() throws {
    let sandbox = try Sandbox(contents: nil)
    defer { sandbox.remove() }
    #expect(
      ContextHookRun.apply(
        file: sandbox.file, executablePath: brewPath, enable: true, now: firstMoment) == nil)
    let written = try #require(sandbox.text)
    #expect(ContextHookSetup.entries(in: Array(written.utf8)).count == 1)
    #expect(sandbox.names == ["settings.json"])
  }

  @Test func applyingToInvalidJSONReturnsTheErrorLineAndWritesNothing() throws {
    let sandbox = try Sandbox(contents: "{ nope")
    defer { sandbox.remove() }
    let line = ContextHookRun.apply(
      file: sandbox.file, executablePath: brewPath, enable: true, now: firstMoment)
    #expect(line?.hasPrefix("\(sandbox.file.path): error: ") == true)
    #expect(sandbox.text == "{ nope")
    #expect(sandbox.names == ["settings.json"])
  }

  @Test func reportsTheHookStatusOfAFile() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    #expect(ContextHookRun.status(file: sandbox.file, executablePath: brewPath) == .notWired)
    _ = ContextHookRun.apply(
      file: sandbox.file, executablePath: brewPath, enable: true, now: firstMoment)
    #expect(ContextHookRun.status(file: sandbox.file, executablePath: brewPath) == .wired)
    let stale = try #require(sandbox.text).replacingOccurrences(
      of: "\"async\": true,", with: "\"async\": false,")
    try Data(stale.utf8).write(to: sandbox.file)
    #expect(ContextHookRun.status(file: sandbox.file, executablePath: brewPath) == .needsUpdate)
    try Data("{ nope".utf8).write(to: sandbox.file)
    guard
      case .unusable(let reason) = ContextHookRun.status(
        file: sandbox.file, executablePath: brewPath)
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
    #expect(ContextHookRun.status(file: sandbox.file, executablePath: brewPath) == .notWired)
  }

  @Test func refusesAnExecutableThatIsNotCountersign() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    let line = ContextHookRun.apply(
      file: sandbox.file, executablePath: "", enable: true, now: firstMoment)
    #expect(line?.hasPrefix("\(sandbox.file.path): error: ") == true)
    #expect(sandbox.text == permissionOnly)
  }
}
