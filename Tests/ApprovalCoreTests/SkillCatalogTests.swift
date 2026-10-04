import Foundation
import Testing

@testable import ApprovalCore

@Suite struct SkillCatalogTests {
  private func data(_ json: String) -> Data {
    Data(json.utf8)
  }

  private func fixtureCatalog() throws -> SkillCatalog {
    let result = SkillCatalog.parse(try FixtureLoader.data("skills-catalog"))
    guard case .success(let catalog) = result else {
      throw FixtureLoader.LoaderError.missing("skills-catalog did not parse")
    }
    return catalog
  }

  private func reason(_ json: String) -> String? {
    guard case .failure(let error) = SkillCatalog.parse(data(json)) else { return nil }
    return error.reason
  }

  private func skillJSON(
    path: String = "skills/a", invocation: String = "model", extra: String = ""
  ) -> String {
    """
    {"schemaVersion": 1, "skills": [
    {"name": "a", "version": "1.0.0", "agents": ["claude"], "description": "d",
     "invocation": "\(invocation)", "path": "\(path)"\(extra)}]}
    """
  }

  private let validSkill =
    #"{"name": "z", "version": "1", "agents": [], "description": "d", "invocation": "model", "path": "skills/z"}"#

  @Test func theFixtureParses() throws {
    let catalog = try fixtureCatalog()

    #expect(
      catalog.skills.map(\.name) == [
        "orchestrate", "context-transfer", "human-voice-writing", "memory-review",
        "codebase-research", "release-notes", "feature-pr-description",
        "promotion-pr-description", "thorough-diff-review", "i18n-translate", "qa-tester",
        "impact-check", "how-it-works", "pr-review-triage", "walkthrough", "writeups-cleanup",
      ])
    #expect(catalog.rules.count == 11)
    #expect(catalog.agents.count == 4)
    #expect(
      catalog.skills[0]
        == SkillCatalog.Skill(
          name: "orchestrate",
          version: "1.0.0",
          agents: ["claude"],
          description:
            "Run work of 3+ independently verifiable commits as an orchestrator: split into units, brief one builder per unit in its own worktree, land and commit each unit, gate once.",
          whenToUse:
            "Use for a task of three or more independently verifiable commits, or on request at any size.",
          invocation: .model,
          path: "skills/orchestrate"))
    #expect(
      catalog.rules[0]
        == SkillCatalog.Rule(
          name: "responses", title: "Responses", agents: ["claude", "codex", "antigravity"],
          path: "rules/responses.md"))
    #expect(
      catalog.agents.map(\.name) == ["builder", "qa", "researcher", "reviewer"])
    #expect(catalog.agents.map(\.model) == ["sonnet", "sonnet", "haiku", "sonnet"])
    #expect(
      catalog.agents.map(\.path) == [
        "agents/builder.md", "agents/qa.md", "agents/researcher.md", "agents/reviewer.md",
      ])
    #expect(catalog.agents.allSatisfy { !$0.description.isEmpty })
  }

  @Test func theManualSkillsAreExactlyTheOnesWithoutWhenToUse() throws {
    let catalog = try fixtureCatalog()
    let manual = catalog.skills.filter { $0.invocation == .manual }

    #expect(
      manual.map(\.name) == [
        "memory-review", "release-notes", "promotion-pr-description", "writeups-cleanup",
      ])
    #expect(manual.allSatisfy { $0.whenToUse == nil })
    #expect(
      catalog.skills.filter { $0.invocation == .model }.allSatisfy { $0.whenToUse != nil })
  }

  @Test func ignoresUnknownKeysAtTheTopLevelAndInEntries() {
    let result = SkillCatalog.parse(
      data(
        """
        {"schemaVersion": 1, "generatedBy": "x",
         "skills": [{"name": "a", "version": "1", "agents": ["claude"], "description": "d",
                     "invocation": "manual", "path": "skills/a", "tags": ["x"]}],
         "rules": [{"name": "r", "title": "R", "agents": [], "path": "rules/r.md", "x": 1}],
         "agents": [{"name": "b", "description": "d", "path": "agents/b.md", "x": null}]}
        """))

    guard case .success(let catalog) = result else {
      Issue.record("expected success")
      return
    }
    #expect(
      catalog.skills == [
        SkillCatalog.Skill(
          name: "a", version: "1", agents: ["claude"], description: "d", whenToUse: nil,
          invocation: .manual, path: "skills/a")
      ])
    #expect(
      catalog.rules == [
        SkillCatalog.Rule(name: "r", title: "R", agents: [], path: "rules/r.md")
      ])
    #expect(
      catalog.agents == [
        SkillCatalog.Agent(name: "b", description: "d", model: nil, path: "agents/b.md")
      ])
  }

  @Test func failsOnInvalidJSON() {
    #expect(reason("not json") == "catalog.json is not valid JSON")
  }

  @Test func failsWhenTheRootIsNotAnObject() {
    #expect(reason("[1, 2]") == "catalog.json does not contain a JSON object")
  }

  @Test func failsWhenSchemaVersionIsMissing() {
    #expect(reason(#"{"skills": []}"#) == "catalog.json is missing schemaVersion")
  }

  @Test func failsWhenSchemaVersionIsNotOne() {
    #expect(reason(#"{"schemaVersion": 2}"#) == "catalog.json has an unknown schemaVersion")
  }

  @Test func aCatalogWithOnlySchemaVersionHasEmptyLists() {
    let result = SkillCatalog.parse(data(#"{"schemaVersion": 1}"#))

    #expect(result == .success(SkillCatalog(skills: [], rules: [], agents: [])))
  }

  @Test func failsWhenAListIsNotAnArray() {
    #expect(
      reason(#"{"schemaVersion": 1, "skills": {}}"#) == "catalog.json skills is not an array")
    #expect(
      reason(#"{"schemaVersion": 1, "rules": "x"}"#) == "catalog.json rules is not an array")
  }

  @Test func failsWhenAnEntryIsNotAnObject() {
    #expect(
      reason(#"{"schemaVersion": 1, "agents": ["x"]}"#)
        == "catalog.json agents[0] is not an object")
  }

  @Test func failsWhenARequiredFieldIsMissing() {
    let json =
      """
      {"schemaVersion": 1, "skills": [\(validSkill),
      {"name": "a", "version": "1", "agents": [], "invocation": "model", "path": "skills/a"}]}
      """

    #expect(reason(json) == "catalog.json skills[1] is missing description")
  }

  @Test func failsWhenAgentsIsNotAnArrayOfStrings() {
    #expect(
      reason(
        #"{"schemaVersion": 1, "rules": [{"name": "r", "title": "R", "agents": [1], "path": "rules/r.md"}]}"#
      ) == "catalog.json rules[0] is missing agents")
  }

  @Test func failsOnAnUnknownInvocation() {
    #expect(
      reason(skillJSON(invocation: "auto")) == "catalog.json skills[0] has an unknown invocation")
  }

  @Test func failsWhenWhenToUseIsNotAString() {
    #expect(
      reason(skillJSON(extra: #", "whenToUse": 3"#))
        == "catalog.json skills[0] is missing whenToUse")
  }

  @Test func failsWhenAnAgentModelIsNotAString() {
    #expect(
      reason(
        #"{"schemaVersion": 1, "agents": [{"name": "b", "description": "d", "model": 1, "path": "agents/b.md"}]}"#
      ) == "catalog.json agents[0] is missing model")
  }

  @Test func nullWhenToUseAndNullModelGiveNil() {
    let result = SkillCatalog.parse(
      data(
        """
        {"schemaVersion": 1,
         "skills": [{"name": "a", "version": "1", "agents": [], "description": "d",
                     "whenToUse": null, "invocation": "manual", "path": "skills/a"}],
         "agents": [{"name": "b", "description": "d", "model": null, "path": "agents/b.md"}]}
        """))

    guard case .success(let catalog) = result else {
      Issue.record("expected success")
      return
    }
    #expect(catalog.skills[0].whenToUse == nil)
    #expect(catalog.agents[0].model == nil)
  }

  @Test func failsOnPathsOutsideTheFolder() {
    let expected = "catalog.json skills[0] has a path outside its folder"

    #expect(reason(skillJSON(path: "/etc/passwd")) == expected)
    #expect(reason(skillJSON(path: "skills/../../x")) == expected)
    #expect(reason(skillJSON(path: "")) == expected)
  }

  @Test func aDotDotInsideAFileNameIsNotAParentComponent() {
    #expect(reason(skillJSON(path: "skills/a..b")) == nil)
  }

  @Test func pathsOutsideTheFolderFailRulesAndAgentsToo() {
    #expect(
      reason(
        #"{"schemaVersion": 1, "rules": [{"name": "r", "title": "R", "agents": [], "path": "../r.md"}]}"#
      ) == "catalog.json rules[0] has a path outside its folder")
    #expect(
      reason(
        #"{"schemaVersion": 1, "agents": [{"name": "b", "description": "d", "path": "/b.md"}]}"#
      ) == "catalog.json agents[0] has a path outside its folder")
  }

  @Test func readsTheCatalogFromAFolder() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("qa-skill-catalog-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FixtureLoader.data("skills-catalog").write(
      to: folder.appendingPathComponent(SkillCatalog.fileName))

    guard case .success(let catalog) = SkillCatalog.read(folder: folder) else {
      Issue.record("expected success")
      return
    }
    #expect(catalog.skills.count == 16)
  }

  @Test func readingAnEmptyFolderNamesTheFolder() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("qa-skill-catalog-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(
      SkillCatalog.read(folder: folder)
        == .failure(SkillCatalogError(reason: "catalog.json is missing in \(folder.path)")))
  }
}
