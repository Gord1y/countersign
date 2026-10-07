import Foundation

public struct UnreadableFolder: Equatable, Sendable {
  public let folder: URL
  public let reason: String
  public let isPermissionDenied: Bool

  public init(folder: URL, reason: String, isPermissionDenied: Bool = false) {
    self.folder = folder
    self.reason = reason
    self.isPermissionDenied = isPermissionDenied
  }
}

public struct SkillsOverview: Equatable, Sendable {
  public enum Availability: Equatable, Sendable {
    case notInstalled
    case waitingForAccess(setupFolder: URL)
    case catalogUnreadable(folder: URL, reason: String)
    case ready(setupFolder: URL)
  }

  public enum AgentStatus: Equatable, Sendable {
    case linked
    case copied(version: String)
    case updateAvailable(installed: String, available: String)
    case notInstalled
    case agentMissing
  }

  public struct AgentInstall: Equatable, Sendable {
    public let agent: String
    public let status: AgentStatus

    public init(agent: String, status: AgentStatus) {
      self.agent = agent
      self.status = status
    }
  }

  public struct Skill: Equatable, Sendable, Identifiable {
    public var id: String { source.path + "/" + name }
    public let name: String
    public let description: String
    public let version: String
    public let source: URL
    public let agents: [AgentInstall]

    public init(
      name: String, description: String, version: String, source: URL, agents: [AgentInstall]
    ) {
      self.name = name
      self.description = description
      self.version = version
      self.source = source
      self.agents = agents
    }
  }

  public struct Rule: Equatable, Sendable, Identifiable {
    public var id: String { source.path + "/" + name }
    public let name: String
    public let title: String
    public let agents: [String]
    public let source: URL

    public init(name: String, title: String, agents: [String], source: URL) {
      self.name = name
      self.title = title
      self.agents = agents
      self.source = source
    }
  }

  public static let updateScriptName = "update.sh"

  public let availability: Availability
  public let skills: [Skill]
  public let rules: [Rule]
  public let additions: [URL]
  public let waitingFolders: [URL]
  public let unreadableFolders: [UnreadableFolder]

  public init(
    availability: Availability, skills: [Skill], rules: [Rule], additions: [URL],
    waitingFolders: [URL] = [], unreadableFolders: [UnreadableFolder] = []
  ) {
    self.availability = availability
    self.skills = skills
    self.rules = rules
    self.additions = additions
    self.waitingFolders = waitingFolders
    self.unreadableFolders = unreadableFolders
  }

  public var updateCommand: String? {
    guard case .ready(let setupFolder) = availability else { return nil }
    let anyUpdate = skills.contains { skill in
      skill.agents.contains { install in
        if case .updateAvailable = install.status { return true }
        return false
      }
    }
    guard anyUpdate else { return nil }
    return setupFolder.appendingPathComponent(Self.updateScriptName).path
  }

  public static func read(
    paths: AppPaths, agentExists: (String) -> Bool, approved: Set<String> = []
  ) -> SkillsOverview {
    let state = SkillsInstallState.read(directory: paths.skillsStateDirectory)
    guard let setupFolder = state.setupFolder else {
      return SkillsOverview(availability: .notInstalled, skills: [], rules: [], additions: [])
    }
    func waits(_ folder: URL) -> Bool {
      GuardedFolder.isGuarded(folder, home: paths.home)
        && !approved.contains(folder.standardizedFileURL.path)
    }
    if waits(setupFolder) {
      return SkillsOverview(
        availability: .waitingForAccess(setupFolder: setupFolder), skills: [], rules: [],
        additions: [], waitingFolders: [setupFolder])
    }
    let setupCatalog: SkillCatalog
    switch SkillCatalog.read(folder: setupFolder) {
    case .success(let catalog):
      setupCatalog = catalog
    case .failure(let error):
      return SkillsOverview(
        availability: .catalogUnreadable(folder: setupFolder, reason: error.reason),
        skills: [], rules: [], additions: [])
    }

    var catalogs: [(folder: URL, catalog: SkillCatalog)] = [(setupFolder, setupCatalog)]
    var additionFolders: [URL] = []
    var waitingFolders: [URL] = []
    var unreadableFolders: [UnreadableFolder] = []
    for folder in state.sources.dropFirst() {
      if waits(folder) {
        waitingFolders.append(folder)
        continue
      }
      switch SkillCatalog.read(folder: folder) {
      case .success(let catalog):
        catalogs.append((folder, catalog))
        additionFolders.append(folder)
      case .failure(let error):
        unreadableFolders.append(
          UnreadableFolder(
            folder: folder, reason: error.reason, isPermissionDenied: error.isPermissionDenied))
      }
    }

    var installedByAgent: [String: [String: InstalledSkill.Kind]] = [:]
    func installedSkills(for agent: String) -> [String: InstalledSkill.Kind] {
      if let known = installedByAgent[agent] { return known }
      var scanned: [String: InstalledSkill.Kind] = [:]
      if let directory = paths.agentSkillsDirectory(for: agent) {
        for skill in InstalledSkill.scan(agent: agent, directory: directory) {
          scanned[skill.name] = skill.kind
        }
      }
      installedByAgent[agent] = scanned
      return scanned
    }

    var skills: [Skill] = []
    var rules: [Rule] = []
    for (folder, catalog) in catalogs {
      for skill in catalog.skills {
        let installs = skill.agents.map { agent in
          AgentInstall(
            agent: agent,
            status: status(
              of: skill, agent: agent, manifest: state.manifest,
              installed: installedSkills(for: agent), agentExists: agentExists,
              hasSkillsFolder: paths.agentSkillsDirectory(for: agent) != nil))
        }
        skills.append(
          Skill(
            name: skill.name, description: skill.description, version: skill.version,
            source: folder, agents: installs))
      }
      for rule in catalog.rules {
        rules.append(Rule(name: rule.name, title: rule.title, agents: rule.agents, source: folder))
      }
    }

    return SkillsOverview(
      availability: .ready(setupFolder: setupFolder), skills: skills, rules: rules,
      additions: additionFolders, waitingFolders: waitingFolders,
      unreadableFolders: unreadableFolders)
  }

  public static func installerAgentExists(_ agent: String, paths: AppPaths) -> Bool {
    let directory: URL?
    switch agent {
    case "claude":
      directory = paths.agentSkillsDirectory(for: "claude")?.deletingLastPathComponent()
    case "codex":
      directory = paths.home.appendingPathComponent(".codex")
    case "antigravity":
      directory = paths.home.appendingPathComponent(".gemini")
        .appendingPathComponent("antigravity-cli")
    default:
      directory = nil
    }
    guard let directory else { return false }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func status(
    of skill: SkillCatalog.Skill,
    agent: String,
    manifest: [SkillsInstallState.ManifestEntry],
    installed: [String: InstalledSkill.Kind],
    agentExists: (String) -> Bool,
    hasSkillsFolder: Bool
  ) -> AgentStatus {
    guard hasSkillsFolder, agentExists(agent) else { return .agentMissing }
    guard let kind = installed[skill.name] else { return .notInstalled }
    switch kind {
    case .linked:
      return .linked
    case .copied:
      let recorded =
        manifest.first { $0.agent == agent && $0.skill == skill.name }?.version ?? skill.version
      if let recordedParts = UpdateCheck.semverParts(recorded),
        let availableParts = UpdateCheck.semverParts(skill.version),
        recordedParts.lexicographicallyPrecedes(availableParts)
      {
        return .updateAvailable(installed: recorded, available: skill.version)
      }
      return .copied(version: recorded)
    }
  }
}
