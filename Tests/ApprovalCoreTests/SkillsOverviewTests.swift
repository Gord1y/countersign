import Foundation
import Testing

@testable import ApprovalCore

@Suite struct SkillsOverviewTests {
  private struct Home {
    let root: URL
    let paths: AppPaths
    let state: URL
    let source: URL

    init() throws {
      root = FileManager.default.temporaryDirectory
        .appendingPathComponent("qa-skills-overview-\(UUID().uuidString)")
      paths = AppPaths(home: root)
      state = paths.skillsStateDirectory
      source = try Self.makeFolder(root.appendingPathComponent("countersign-skills"))
    }

    static func makeFolder(_ folder: URL) throws -> URL {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      return URL(fileURLWithPath: folder.path)
    }

    func cleanUp() {
      try? FileManager.default.removeItem(at: root)
    }

    func writeCatalog(to folder: URL) throws {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try FixtureLoader.data("skills-catalog").write(
        to: folder.appendingPathComponent(SkillCatalog.fileName))
    }

    func writeSources(_ folders: [URL]) throws {
      try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
      let text = folders.map(\.path).joined(separator: "\n") + "\n"
      try Data(text.utf8).write(
        to: state.appendingPathComponent(SkillsInstallState.sourcesFileName))
    }

    func writeManifest(_ entries: [(agent: String, skill: String, version: String)]) throws {
      let lines = entries.map { entry in
        [entry.agent, entry.skill, entry.version, "SKILL.md", String(repeating: "a", count: 64)]
          .joined(separator: "\t")
      }
      try Data((lines.joined(separator: "\n") + "\n").utf8).write(
        to: state.appendingPathComponent(SkillsInstallState.manifestFileName))
    }

    func link(skill: String, agent: String) throws {
      let directory = try #require(paths.agentSkillsDirectory(for: agent))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(
        at: directory.appendingPathComponent(skill),
        withDestinationURL: source.appendingPathComponent("skills").appendingPathComponent(skill))
    }

    func copy(skill: String, agent: String) throws {
      let directory = try #require(paths.agentSkillsDirectory(for: agent))
      try FileManager.default.createDirectory(
        at: directory.appendingPathComponent(skill), withIntermediateDirectories: true)
    }

    func makeAgentFolder(_ relativePath: String) throws {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(relativePath), withIntermediateDirectories: true)
    }
  }

  private func status(_ overview: SkillsOverview, skill: String, agent: String)
    -> SkillsOverview.AgentStatus?
  {
    overview.skills.first { $0.name == skill }?.agents.first { $0.agent == agent }?.status
  }

  @Test func withoutAStateFolderNothingIsInstalled() throws {
    let home = try Home()
    defer { home.cleanUp() }

    let overview = SkillsOverview.read(paths: home.paths, agentExists: { _ in true })

    #expect(overview.availability == .notInstalled)
    #expect(overview.skills.isEmpty)
    #expect(overview.rules.isEmpty)
    #expect(overview.additions.isEmpty)
    #expect(overview.updateCommand == nil)
  }

  @Test func anUnreadableCatalogCarriesTheParsersReason() throws {
    let home = try Home()
    defer { home.cleanUp() }
    try home.writeSources([home.source])
    try Data("not json".utf8).write(
      to: home.source.appendingPathComponent(SkillCatalog.fileName))

    let overview = SkillsOverview.read(paths: home.paths, agentExists: { _ in true })

    #expect(
      overview.availability
        == .catalogUnreadable(folder: home.source, reason: "catalog.json is not valid JSON"))
    #expect(overview.skills.isEmpty)
    #expect(overview.rules.isEmpty)
  }

  @Test func aLinkedInstallShowsLinkedMissingAndAbsentAgents() throws {
    let home = try Home()
    defer { home.cleanUp() }
    try home.writeCatalog(to: home.source)
    try home.writeSources([home.source])
    try home.makeAgentFolder(".claude")
    try home.link(skill: "orchestrate", agent: "claude")

    let overview = SkillsOverview.read(
      paths: home.paths, agentExists: { SkillsOverview.installerAgentExists($0, paths: home.paths) }
    )

    #expect(overview.availability == .ready(setupFolder: home.source))
    #expect(overview.skills.count == 16)
    #expect(overview.rules.count == 11)
    #expect(status(overview, skill: "orchestrate", agent: "claude") == .linked)
    #expect(status(overview, skill: "memory-review", agent: "claude") == .notInstalled)
    #expect(status(overview, skill: "context-transfer", agent: "codex") == .agentMissing)
    #expect(overview.updateCommand == nil)
  }

  @Test func aCopiedSkillBehindItsCatalogOffersTheUpdateCommand() throws {
    let home = try Home()
    defer { home.cleanUp() }
    try home.writeCatalog(to: home.source)
    try home.writeSources([home.source])
    try home.copy(skill: "orchestrate", agent: "claude")
    try home.copy(skill: "context-transfer", agent: "claude")
    try home.copy(skill: "context-transfer", agent: "codex")
    try home.writeManifest([
      (agent: "claude", skill: "orchestrate", version: "0.9.0"),
      (agent: "claude", skill: "context-transfer", version: "0.9.0"),
      (agent: "codex", skill: "context-transfer", version: "1.0.0"),
    ])

    let behind = SkillsOverview.read(paths: home.paths, agentExists: { _ in true })

    #expect(
      status(behind, skill: "orchestrate", agent: "claude")
        == .updateAvailable(installed: "0.9.0", available: "1.0.0"))
    #expect(
      status(behind, skill: "context-transfer", agent: "claude")
        == .updateAvailable(installed: "0.9.0", available: "1.0.0"))
    #expect(
      status(behind, skill: "context-transfer", agent: "codex") == .copied(version: "1.0.0"))
    #expect(behind.updateCommand?.hasSuffix("/update.sh") == true)

    try home.writeManifest([
      (agent: "claude", skill: "orchestrate", version: "1.0.0"),
      (agent: "claude", skill: "context-transfer", version: "1.0.0"),
      (agent: "codex", skill: "context-transfer", version: "1.0.0"),
    ])

    let current = SkillsOverview.read(paths: home.paths, agentExists: { _ in true })

    #expect(
      status(current, skill: "orchestrate", agent: "claude") == .copied(version: "1.0.0"))
    #expect(current.updateCommand == nil)
  }

  @Test func additionsFollowTheSetupFolderAndOneWithoutACatalogIsStillListed() throws {
    let home = try Home()
    defer { home.cleanUp() }
    let withCatalog = try Home.makeFolder(home.root.appendingPathComponent("addition-with"))
    let withoutCatalog = try Home.makeFolder(home.root.appendingPathComponent("addition-without"))
    try home.writeCatalog(to: home.source)
    try home.writeCatalog(to: withCatalog)
    try home.writeSources([home.source, withCatalog, withoutCatalog])

    let overview = SkillsOverview.read(paths: home.paths, agentExists: { _ in true })

    #expect(overview.skills.count == 32)
    #expect(overview.skills.prefix(16).allSatisfy { $0.source == home.source })
    #expect(overview.skills.suffix(16).allSatisfy { $0.source == withCatalog })
    #expect(overview.rules.count == 22)
    #expect(overview.additions == [withCatalog, withoutCatalog])
  }

  @Test func installerAgentExistsFollowsTheInstallersFolders() throws {
    let home = try Home()
    defer { home.cleanUp() }

    #expect(!SkillsOverview.installerAgentExists("claude", paths: home.paths))
    #expect(!SkillsOverview.installerAgentExists("codex", paths: home.paths))
    #expect(!SkillsOverview.installerAgentExists("antigravity", paths: home.paths))

    try home.makeAgentFolder(".claude")
    try home.makeAgentFolder(".codex")
    try home.makeAgentFolder(".gemini/antigravity-cli")

    #expect(SkillsOverview.installerAgentExists("claude", paths: home.paths))
    #expect(SkillsOverview.installerAgentExists("codex", paths: home.paths))
    #expect(SkillsOverview.installerAgentExists("antigravity", paths: home.paths))
    #expect(!SkillsOverview.installerAgentExists("cursor", paths: home.paths))

    let customConfig = home.root.appendingPathComponent("custom-claude")
    let relocated = AppPaths(home: home.root, claudeConfigDir: customConfig.path)

    #expect(!SkillsOverview.installerAgentExists("claude", paths: relocated))

    _ = try Home.makeFolder(customConfig)

    #expect(SkillsOverview.installerAgentExists("claude", paths: relocated))
  }
}
