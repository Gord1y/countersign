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
  let location: HookConfigLocation

  init(contents: String?) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-waiting-hook-run-\(UUID().uuidString)")
      .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    file = directory.appendingPathComponent("settings.json")
    if let contents {
      try Data(contents.utf8).write(to: file)
    }
    location = HookConfigLocation(host: .claude, directory: directory, file: file)
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

@Suite struct WaitingHookRunTests {
  @Test func previewsTheDiffForTurningOnIntoAFileWithoutTheEntry() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    let preview = WaitingHookRun.preview(
      locations: [sandbox.location], executablePath: brewPath, enable: true)
    #expect(preview.failures.isEmpty)
    #expect(preview.changedFiles == [sandbox.file])
    #expect(preview.text.hasPrefix(sandbox.file.path + "\n"))
    #expect(preview.text.contains("+    \"Stop\": ["))
    #expect(preview.text.contains("--event waiting"))
    #expect(preview.text.contains("\"timeout\": 30"))
    #expect(sandbox.text == permissionOnly)
  }

  @Test func previewsTheDiffForTurningOffAndNothingToDoWhenThereIsNoEntry() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    let nothing = WaitingHookRun.preview(
      locations: [sandbox.location], executablePath: brewPath, enable: false)
    #expect(!nothing.hasChanges)
    #expect(nothing.text == "\(sandbox.file.path): already up to date\n")
    #expect(
      WaitingHookRun.apply(
        locations: [sandbox.location], executablePath: brewPath, enable: true, now: firstMoment
      )
      .isEmpty)
    let off = WaitingHookRun.preview(
      locations: [sandbox.location], executablePath: brewPath, enable: false)
    #expect(off.changedFiles == [sandbox.file])
    #expect(off.text.contains("-    \"Stop\": ["))
  }

  @Test func previewsNothingWithoutLocations() {
    let preview = WaitingHookRun.preview(locations: [], executablePath: brewPath, enable: true)
    #expect(preview.text.isEmpty)
    #expect(!preview.hasChanges)
    #expect(preview.failures.isEmpty)
  }

  @Test func previewReportsAFileThatIsNotJSON() throws {
    let sandbox = try Sandbox(contents: "not json")
    defer { sandbox.remove() }
    let preview = WaitingHookRun.preview(
      locations: [sandbox.location], executablePath: brewPath, enable: true)
    #expect(preview.failures.count == 1)
    #expect(preview.failures[0].hasPrefix("\(sandbox.file.path): error: "))
    #expect(!preview.hasChanges)
  }

  @Test func applyWritesWithABackupAndTurningOffRestoresTheBytes() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    #expect(
      WaitingHookRun.apply(
        locations: [sandbox.location], executablePath: brewPath, enable: true, now: firstMoment
      )
      .isEmpty)
    let enabled = try #require(sandbox.text)
    #expect(enabled != permissionOnly)
    #expect(WaitingHookSetup.entries(in: Array(enabled.utf8), host: .claude).count == 1)
    #expect(sandbox.names.count == 2)
    #expect(
      WaitingHookRun.apply(
        locations: [sandbox.location], executablePath: brewPath, enable: false, now: secondMoment
      )
      .isEmpty)
    #expect(sandbox.text == permissionOnly)
    #expect(sandbox.names.count == 3)
  }

  @Test func applyingTwiceWritesNothingTheSecondTime() throws {
    let sandbox = try Sandbox(contents: permissionOnly)
    defer { sandbox.remove() }
    _ = WaitingHookRun.apply(
      locations: [sandbox.location], executablePath: brewPath, enable: true, now: firstMoment)
    let names = sandbox.names
    #expect(
      WaitingHookRun.apply(
        locations: [sandbox.location], executablePath: brewPath, enable: true, now: secondMoment
      )
      .isEmpty)
    #expect(sandbox.names == names)
  }

  @Test func applyReportsAFailureLineForAFileThatIsNotJSON() throws {
    let sandbox = try Sandbox(contents: "not json")
    defer { sandbox.remove() }
    let failures = WaitingHookRun.apply(
      locations: [sandbox.location], executablePath: brewPath, enable: true, now: firstMoment)
    #expect(failures.count == 1)
    #expect(failures[0].hasPrefix("\(sandbox.file.path): error: "))
    #expect(sandbox.text == "not json")
  }

  @Test func applySavesTheCodexStopTrustRecordAndTurningOffDeletesIt() throws {
    let sandbox = try Sandbox(contents: nil)
    defer { sandbox.remove() }
    try Data(
      try HookSetup.install(into: nil, host: .codex, executablePath: brewPath)
    ).write(to: sandbox.file)
    let location = HookConfigLocation(
      host: .codex, directory: sandbox.directory, file: sandbox.file)
    let recordFile = sandbox.directory.appendingPathComponent("waiting-trust.json")
    let failures = WaitingHookRun.apply(
      locations: [location], executablePath: brewPath, enable: true, now: firstMoment,
      codexWaitingTrustFile: recordFile)
    #expect(failures.isEmpty)
    let record = try #require(CodexHookTrustRecordStore.load(file: recordFile))
    #expect(record.hookKey == "\(sandbox.file.path):stop:0:0")
    #expect(record.command == "\(brewPath) hook --host codex --event waiting")
    #expect(
      WaitingHookRun.apply(
        locations: [location], executablePath: brewPath, enable: false, now: secondMoment,
        codexWaitingTrustFile: recordFile
      ).isEmpty)
    #expect(CodexHookTrustRecordStore.load(file: recordFile) == nil)
  }

  @Test func statusIsWiredOnlyWhenEveryLocationHasTheEntry() throws {
    let wired = try Sandbox(contents: permissionOnly)
    let bare = try Sandbox(contents: permissionOnly)
    defer {
      wired.remove()
      bare.remove()
    }
    #expect(WaitingHookRun.status(locations: [], executablePath: brewPath) == .notWired)
    #expect(
      WaitingHookRun.status(locations: [wired.location], executablePath: brewPath) == .notWired)
    _ = WaitingHookRun.apply(
      locations: [wired.location], executablePath: brewPath, enable: true, now: firstMoment)
    #expect(WaitingHookRun.status(locations: [wired.location], executablePath: brewPath) == .wired)
    #expect(
      WaitingHookRun.status(
        locations: [wired.location, bare.location], executablePath: brewPath) == .notWired)
    #expect(
      WaitingHookRun.status(locations: [wired.location], executablePath: "/elsewhere/countersign")
        == .needsUpdate)
  }
}
