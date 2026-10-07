import Foundation
import Testing

@testable import ApprovalCore

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("countersign-config-store-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url.resolvingSymlinksInPath()
}

private func permissions(of url: URL) throws -> Int {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func contents(of url: URL) throws -> String {
  String(decoding: try Data(contentsOf: url), as: UTF8.self)
}

private let utc = TimeZone(identifier: "UTC") ?? .current
private let moment = Date(timeIntervalSince1970: 1_790_000_000)

@Suite struct ConfigFileStoreTests {
  @Test func namesTheBackupAfterTheFileAndTheTime() {
    #expect(
      ConfigFileStore.backupName(for: "settings.json", date: moment, timeZone: utc)
        == "settings.json.countersign-20260921-141320.bak")
    let kyiv = TimeZone(secondsFromGMT: 3 * 3600) ?? utc
    #expect(
      ConfigFileStore.backupName(for: "hooks.json", date: moment, timeZone: kyiv)
        == "hooks.json.countersign-20260921-171320.bak")
  }

  @Test func readsAMissingFileAsNothing() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try ConfigFileStore.read(directory.appendingPathComponent("settings.json")) == nil)
    let file = directory.appendingPathComponent("hooks.json")
    try Data("{}".utf8).write(to: file)
    #expect(try ConfigFileStore.read(file) == Array("{}".utf8))
    #expect(throws: (any Error).self) { try ConfigFileStore.read(directory) }
    #expect(
      ConfigFileStore.fileState(directory.appendingPathComponent("settings.json")) == .missing)
    #expect(ConfigFileStore.fileState(file) == .bytes(Array("{}".utf8)))
    guard case .unreadable(let reason) = ConfigFileStore.fileState(directory) else {
      Issue.record("a directory reads as unreadable")
      return
    }
    #expect(!reason.isEmpty)
  }

  @Test func createsAMissingFileWithoutABackup() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    let backup = try ConfigFileStore.write(Array("{}\n".utf8), to: file, date: moment)
    #expect(backup == nil)
    #expect(try contents(of: file) == "{}\n")
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["settings.json"])
  }

  @Test func backsUpAnExistingFileAndKeepsItsPermissions() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try Data("old".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let backup = try ConfigFileStore.write(
      Array("new".utf8), to: file, date: moment, timeZone: utc)
    #expect(backup?.lastPathComponent == "settings.json.countersign-20260921-141320.bak")
    #expect(try contents(of: file) == "new")
    #expect(try permissions(of: file) == 0o600)
    let backupFile = try #require(backup)
    #expect(try contents(of: backupFile) == "old")
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(names == ["settings.json", "settings.json.countersign-20260921-141320.bak"])
  }

  @Test func skipsTheBackupWhenAskedAndKeepsThePermissions() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("config.json")
    try Data("old".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let name = ConfigFileStore.backupName(for: "config.json", date: moment, timeZone: utc)
    try Data("earlier".utf8).write(to: directory.appendingPathComponent(name))
    let backup = try ConfigFileStore.write(
      Array("new".utf8), to: file, date: moment, timeZone: utc, backingUp: false)
    #expect(backup == nil)
    #expect(try contents(of: file) == "new")
    #expect(try permissions(of: file) == 0o600)
    #expect(try contents(of: directory.appendingPathComponent(name)) == "earlier")
  }

  @Test func keepsWidePermissionsThatTheUmaskWouldNarrow() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("hooks.json")
    try Data("old".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: file.path)
    try ConfigFileStore.write(Array("new".utf8), to: file, date: moment)
    #expect(try permissions(of: file) == 0o666)
  }

  @Test func writesThroughASymlinkAndKeepsTheLink() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let dotfiles = directory.appendingPathComponent("dotfiles")
    let home = directory.appendingPathComponent("home")
    try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let target = dotfiles.appendingPathComponent("settings.json")
    let link = home.appendingPathComponent("settings.json")
    try Data("old".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let backup = try ConfigFileStore.write(Array("new".utf8), to: link, date: moment)
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try contents(of: target) == "new")
    #expect(backup?.deletingLastPathComponent().path == dotfiles.path)
  }

  @Test func keepsOnlyTheThreeNewestBackupsOfTheFile() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try Data("v0".utf8).write(to: file)
    let unrelated = [
      "hooks.json.countersign-20200101-000000.bak", "settings.json.countersign-keep.bak",
    ]
    for name in unrelated {
      try Data("other".utf8).write(to: directory.appendingPathComponent(name))
    }
    let dates = (0..<5).map { moment.addingTimeInterval(Double($0) * 60) }
    for (index, date) in dates.enumerated() {
      try ConfigFileStore.write(Array("v\(index + 1)".utf8), to: file, date: date, timeZone: utc)
    }
    let kept = dates.suffix(3).map {
      ConfigFileStore.backupName(for: "settings.json", date: $0, timeZone: utc)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(names == (["settings.json"] + kept + unrelated).sorted())
    #expect(try contents(of: directory.appendingPathComponent(kept[0])) == "v2")
    #expect(try contents(of: file) == "v5")
  }

  @Test func keepsBothBackupsWhenTwoWritesShareASecond() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try Data("v0".utf8).write(to: file)
    let first = try ConfigFileStore.write(Array("v1".utf8), to: file, date: moment, timeZone: utc)
    let second = try ConfigFileStore.write(Array("v2".utf8), to: file, date: moment, timeZone: utc)
    let third = try ConfigFileStore.write(Array("v3".utf8), to: file, date: moment, timeZone: utc)
    #expect(first?.lastPathComponent == "settings.json.countersign-20260921-141320.bak")
    #expect(second?.lastPathComponent == "settings.json.countersign-20260921-141320-2.bak")
    #expect(third?.lastPathComponent == "settings.json.countersign-20260921-141320-3.bak")
    #expect(try first.map(contents(of:)) == "v0")
    #expect(try second.map(contents(of:)) == "v1")
    #expect(try contents(of: file) == "v3")
  }

  @Test func prunesSuffixedBackupsInWriteOrder() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try Data("v0".utf8).write(to: file)
    let later = moment.addingTimeInterval(60)
    let dates = [moment, moment, moment, later, later]
    var written: [URL] = []
    for (index, date) in dates.enumerated() {
      let backup = try ConfigFileStore.write(
        Array("v\(index + 1)".utf8), to: file, date: date, timeZone: utc)
      written.append(try #require(backup))
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    let kept = written.suffix(3).map(\.lastPathComponent)
    #expect(names == (["settings.json"] + kept).sorted())
    #expect(
      kept == [
        "settings.json.countersign-20260921-141320-3.bak",
        "settings.json.countersign-20260921-141420.bak",
        "settings.json.countersign-20260921-141420-2.bak",
      ])
  }

  @Test func failsWhenTheDirectoryIsMissing() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("missing").appendingPathComponent("hooks.json")
    #expect(throws: POSIXError.self) {
      try ConfigFileStore.write(Array("{}".utf8), to: file, date: moment)
    }
  }

  @Test func failsWhenAParentIsAFile() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let parent = directory.appendingPathComponent("codex")
    try Data("not a directory".utf8).write(to: parent)
    #expect(throws: POSIXError(.ENOTDIR)) {
      try ConfigFileStore.write(
        Array("{}".utf8), to: parent.appendingPathComponent("hooks.json"), date: moment)
    }
  }

  @Test func leavesNoTemporaryFileWhenTheRenameFails() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("settings.json")
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    try Data("inside".utf8).write(to: file.appendingPathComponent("keep"))
    #expect(throws: POSIXError.self) {
      try ConfigFileStore.write(Array("{}".utf8), to: file, date: moment, timeZone: utc)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(names == ["settings.json", "settings.json.countersign-20260921-141320.bak"])
    #expect(try contents(of: file.appendingPathComponent("keep")) == "inside")
  }
}
