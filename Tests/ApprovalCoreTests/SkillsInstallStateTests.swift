import Foundation
import Testing

@testable import ApprovalCore

@Suite struct SkillsInstallStateTests {
  private let validHash = String(repeating: "a", count: 64)

  private func fixtureText(_ name: String) throws -> String {
    String(decoding: try FixtureLoader.data(name, withExtension: "tsv"), as: UTF8.self)
  }

  private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("skills-state-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  @Test func manifestFixtureGivesEveryEntry() throws {
    let entries = SkillsInstallState.manifestEntries(from: try fixtureText("skills-manifest"))
    #expect(entries.count == 81)
    #expect(
      entries.first
        == SkillsInstallState.ManifestEntry(
          agent: "claude", skill: "orchestrate", version: "1.0.0", file: "SKILL.md",
          sha256: "94ce106dd9c9b9bf3c89ec6854285de81e82cd53be21f1edffa499c10f402c5a"))
    #expect(
      entries.last
        == SkillsInstallState.ManifestEntry(
          agent: "antigravity", skill: "writeups-cleanup", version: "1.0.0", file: "SKILL.md",
          sha256: "cea5d50b23861ca76cee1f1d814db3a9ff079abd82e0d9bb8a683c48e438f349"))
    func distinctSkills(for agent: String) -> Int {
      Set(entries.filter { $0.agent == agent }.map(\.skill)).count
    }
    #expect(distinctSkills(for: "claude") == 16)
    #expect(distinctSkills(for: "codex") == 14)
    #expect(distinctSkills(for: "antigravity") == 10)
  }

  @Test func manifestEntriesSkipMalformedLines() {
    let valid = "claude\tmid\t1.0.0\tSKILL.md\t\(validHash)"
    let text = [
      "claude\tshort\t1.0.0\t\(validHash)",
      valid,
      "claude\tlong\t1.0.0\tSKILL.md\t\(validHash)\textra",
      "claude\tshorthash\t1.0.0\tSKILL.md\t\(String(validHash.dropFirst()))",
      "claude\tupper\t1.0.0\tSKILL.md\t\(String(repeating: "A", count: 64))",
    ].joined(separator: "\n")
    let entries = SkillsInstallState.manifestEntries(from: text)
    #expect(
      entries == [
        SkillsInstallState.ManifestEntry(
          agent: "claude", skill: "mid", version: "1.0.0", file: "SKILL.md", sha256: validHash)
      ])
  }

  @Test func sourcesFixtureGivesTheFoldersInOrder() throws {
    let state = SkillsInstallState(
      sources: SkillsInstallState.folderList(from: try fixtureText("skills-sources")),
      additions: [], manifest: [], backups: [])
    #expect(
      state.sources.map(\.path) == [
        "/Users/dev/Projects/countersign-skills", "/Users/dev/Projects/countersign-profile",
      ])
    #expect(state.setupFolder?.path == "/Users/dev/Projects/countersign-skills")
  }

  @Test func folderListSkipsBlankAndRelativeLinesAndTrimsTrailingSpaces() {
    let text = "/Users/dev/a  \n\n   \nrelative/path\n/Users/dev/b\t\n"
    #expect(
      SkillsInstallState.folderList(from: text).map(\.path) == ["/Users/dev/a", "/Users/dev/b"])
  }

  @Test func readCombinesTheFilesOfAFolder() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for (fixture, file) in [
      ("skills-sources", "sources.tsv"), ("skills-additions", "additions.tsv"),
      ("skills-manifest", "manifest.tsv"),
    ] {
      try FixtureLoader.data(fixture, withExtension: "tsv")
        .write(to: directory.appendingPathComponent(file))
    }
    let backups = directory.appendingPathComponent("backups")
    for name in ["20261004-001707", "20261004-020428", ".tmp"] {
      try FileManager.default.createDirectory(
        at: backups.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    try Data("notes".utf8).write(to: backups.appendingPathComponent("notes.txt"))
    let state = SkillsInstallState.read(directory: directory)
    #expect(state.sources.count == 2)
    #expect(state.additions.count == 1)
    #expect(state.manifest.count == 81)
    #expect(state.backups == ["20261004-020428", "20261004-001707"])
  }

  @Test func readOfAMissingFolderIsEmpty() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("absent-\(UUID().uuidString)")
    let state = SkillsInstallState.read(directory: directory)
    #expect(state.sources.isEmpty)
    #expect(state.additions.isEmpty)
    #expect(state.manifest.isEmpty)
    #expect(state.backups.isEmpty)
    #expect(state.setupFolder == nil)
  }

  @Test func scanTellsLinkedCopiedAndSkipsTheRest() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let skills = directory.appendingPathComponent("skills")
    try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: true)
    let absoluteTarget = directory.appendingPathComponent("source/alpha")
    try FileManager.default.createSymbolicLink(
      atPath: skills.appendingPathComponent("alpha").path,
      withDestinationPath: absoluteTarget.path)
    try FileManager.default.createSymbolicLink(
      atPath: skills.appendingPathComponent("beta").path, withDestinationPath: "../src/beta")
    try FileManager.default.createDirectory(
      at: skills.appendingPathComponent("gamma"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: skills.appendingPathComponent(".cache"), withIntermediateDirectories: true)
    try Data("readme".utf8).write(to: skills.appendingPathComponent("readme.md"))

    let installed = InstalledSkill.scan(agent: "claude", directory: skills)
    #expect(installed.map(\.name) == ["alpha", "beta", "gamma"])
    try #require(installed.count == 3)
    #expect(installed.allSatisfy { $0.agent == "claude" })
    guard case .linked(let alphaTarget) = installed[0].kind else {
      Issue.record("alpha is not linked")
      return
    }
    #expect(alphaTarget.path == absoluteTarget.standardizedFileURL.path)
    guard case .linked(let betaTarget) = installed[1].kind else {
      Issue.record("beta is not linked")
      return
    }
    #expect(
      betaTarget.path == directory.appendingPathComponent("src/beta").standardizedFileURL.path)
    #expect(installed[2].kind == .copied)
  }

  @Test func scanOfAMissingFolderIsEmpty() {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("absent-\(UUID().uuidString)")
    #expect(InstalledSkill.scan(agent: "codex", directory: directory).isEmpty)
  }
}
