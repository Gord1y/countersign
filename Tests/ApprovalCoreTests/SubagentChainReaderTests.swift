import Foundation
import Testing

@testable import ApprovalCore

private struct ChainFixture {
  let root: URL
  let sessionID = "session"

  var transcriptPath: String { transcriptURL.path }
  private var transcriptURL: URL { root.appendingPathComponent("\(sessionID).jsonl") }
  private var subagentsDirectory: URL {
    root.appendingPathComponent(sessionID).appendingPathComponent("subagents")
  }

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-chain-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: subagentsDirectory, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }

  func writeMainTranscript(spawning toolUseID: String) throws {
    try transcriptLine(toolUseID: toolUseID)
      .write(to: transcriptURL, atomically: true, encoding: .utf8)
  }

  func writeAgentTranscript(agentID: String, spawning toolUseID: String) throws {
    let url = subagentsDirectory.appendingPathComponent("agent-\(agentID).jsonl")
    try transcriptLine(toolUseID: toolUseID)
      .write(to: url, atomically: true, encoding: .utf8)
  }

  func writeEmptyAgentTranscript(agentID: String) throws {
    let url = subagentsDirectory.appendingPathComponent("agent-\(agentID).jsonl")
    try "".write(to: url, atomically: true, encoding: .utf8)
  }

  func writeMeta(
    agentID: String, agentType: String, description: String, toolUseID: String, spawnDepth: Int
  ) throws {
    let json = """
      {"agentType":"\(agentType)","description":"\(description)","toolUseId":"\(toolUseID)","spawnDepth":\(spawnDepth),"model":"sonnet"}
      """
    let url = subagentsDirectory.appendingPathComponent("agent-\(agentID).meta.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
  }

  func writeRawMeta(agentID: String, json: String) throws {
    let url = subagentsDirectory.appendingPathComponent("agent-\(agentID).meta.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
  }

  private func transcriptLine(toolUseID: String) -> String {
    """
    {"parentUuid":null,"isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","id":"\(toolUseID)","name":"Agent","input":{"description":"spawn","subagent_type":"general-purpose"}}]}}
    """
  }
}

@Suite struct SubagentChainReaderTests {
  @Test func depthOneChainResolvesFromTheMainTranscript() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_root")
    try fixture.writeMeta(
      agentID: "agent1", agentType: "general-purpose", description: "Do the thing",
      toolUseID: "toolu_root", spawnDepth: 1)

    let chain = SubagentChainReader.chain(
      transcriptPath: fixture.transcriptPath, agentID: "agent1")
    #expect(
      chain == [
        SubagentChainLink(
          agentID: "agent1", agentType: "general-purpose", description: "Do the thing")
      ])
  }

  @Test func depthTwoChainWalksThroughTheParentTranscript() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_depth1")
    try fixture.writeMeta(
      agentID: "parent", agentType: "general-purpose", description: "Top level task",
      toolUseID: "toolu_depth1", spawnDepth: 1)
    try fixture.writeAgentTranscript(agentID: "parent", spawning: "toolu_depth2")
    try fixture.writeMeta(
      agentID: "child", agentType: "Explore", description: "Nested task",
      toolUseID: "toolu_depth2", spawnDepth: 2)

    let chain = SubagentChainReader.chain(
      transcriptPath: fixture.transcriptPath, agentID: "child")
    #expect(
      chain == [
        SubagentChainLink(
          agentID: "parent", agentType: "general-purpose", description: "Top level task"),
        SubagentChainLink(agentID: "child", agentType: "Explore", description: "Nested task"),
      ])
  }

  @Test func missingMetaFileForTheRequestingAgentIsNil() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_root")

    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "missing")
        == nil)
  }

  @Test func missingFieldInMetaIsNil() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_root")
    try fixture.writeRawMeta(
      agentID: "agent1", json: #"{"agentType":"general-purpose","spawnDepth":1}"#)

    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "agent1")
        == nil)
  }

  @Test func malformedMetaJSONIsNil() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_root")
    try fixture.writeRawMeta(agentID: "agent1", json: "not json")

    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "agent1")
        == nil)
  }

  @Test func aToolUseIdThatAppearsNowhereIsNil() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_unrelated")
    try fixture.writeMeta(
      agentID: "agent1", agentType: "general-purpose", description: "Orphaned",
      toolUseID: "toolu_root", spawnDepth: 2)

    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "agent1")
        == nil)
  }

  @Test func aDepthThreeChainFollowsParentAgentIdWithoutOpeningAnyTranscript() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeRawMeta(
      agentID: "leaf",
      json: String(decoding: try FixtureLoader.data("claude-subagent-meta-child"), as: UTF8.self)
        .replacingOccurrences(of: "a2f187b802690c409", with: "middle"))
    try fixture.writeRawMeta(
      agentID: "middle",
      json:
        #"{"agentType":"general-purpose","description":"Middle","toolUseId":"toolu_middle","parentAgentId":"top","spawnDepth":2}"#
    )
    try fixture.writeRawMeta(
      agentID: "top",
      json: String(decoding: try FixtureLoader.data("claude-subagent-meta-root"), as: UTF8.self))

    #expect(!FileManager.default.fileExists(atPath: fixture.transcriptPath))
    let chain = SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "leaf")
    #expect(chain?.map(\.agentID) == ["top", "middle", "leaf"])
    #expect(chain?.map(\.agentType) == ["Explore", "general-purpose", "general-purpose"])
  }

  @Test func spawnDepthOneWithoutAParentEndsAtTheMainSessionWithoutReadingItsTranscript() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeRawMeta(
      agentID: "top",
      json: String(decoding: try FixtureLoader.data("claude-subagent-meta-root"), as: UTF8.self))

    #expect(!FileManager.default.fileExists(atPath: fixture.transcriptPath))
    let chain = SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "top")
    #expect(chain?.map(\.agentID) == ["top"])
  }

  @Test func aMissingSpawnDepthFallsBackToTheTranscriptWalk() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_depth1")
    try fixture.writeRawMeta(
      agentID: "parent",
      json:
        #"{"agentType":"general-purpose","description":"Top level task","toolUseId":"toolu_depth1"}"#
    )
    try fixture.writeAgentTranscript(agentID: "parent", spawning: "toolu_depth2")
    try fixture.writeRawMeta(
      agentID: "child",
      json:
        #"{"agentType":"Explore","description":"Nested task","toolUseId":"toolu_depth2"}"#)

    let chain = SubagentChainReader.chain(
      transcriptPath: fixture.transcriptPath, agentID: "child")
    #expect(chain?.map(\.agentID) == ["parent", "child"])
  }

  @Test func aCycleOfParentAgentIdsIsNil() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeRawMeta(
      agentID: "a",
      json:
        #"{"agentType":"general-purpose","description":"A","toolUseId":"toolu_a","parentAgentId":"b","spawnDepth":2}"#
    )
    try fixture.writeRawMeta(
      agentID: "b",
      json:
        #"{"agentType":"general-purpose","description":"B","toolUseId":"toolu_b","parentAgentId":"a","spawnDepth":3}"#
    )

    #expect(SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "a") == nil)
  }

  @Test func missingSubagentsDirectoryIsNil() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_unrelated")

    let missingSessionPath = fixture.root.appendingPathComponent("missing.jsonl").path
    #expect(
      SubagentChainReader.chain(transcriptPath: missingSessionPath, agentID: "agent1") == nil)
  }

  @Test func aCycleBetweenTwoAgentsIsNilRatherThanHanging() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_never_matches")
    try fixture.writeMeta(
      agentID: "a", agentType: "general-purpose", description: "A",
      toolUseID: "toolu_a_to_b", spawnDepth: 2)
    try fixture.writeMeta(
      agentID: "b", agentType: "general-purpose", description: "B",
      toolUseID: "toolu_b_to_a", spawnDepth: 2)
    try fixture.writeAgentTranscript(agentID: "a", spawning: "toolu_b_to_a")
    try fixture.writeAgentTranscript(agentID: "b", spawning: "toolu_a_to_b")

    #expect(SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "a") == nil)
  }

  @Test func aChainDeeperThanTheCapIsNil() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    let depth = 12
    try fixture.writeMainTranscript(spawning: "toolu_0")
    try fixture.writeMeta(
      agentID: "agent0", agentType: "general-purpose", description: "Level 0",
      toolUseID: "toolu_0", spawnDepth: 1)
    for level in 1..<depth {
      let agentID = "agent\(level)"
      let parentID = "agent\(level - 1)"
      let toolUseID = "toolu_\(level)"
      try fixture.writeAgentTranscript(agentID: parentID, spawning: toolUseID)
      try fixture.writeMeta(
        agentID: agentID, agentType: "general-purpose", description: "Level \(level)",
        toolUseID: toolUseID, spawnDepth: level + 1)
    }

    let leafID = "agent\(depth - 1)"
    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: leafID) == nil)
  }

  @Test func theSubagentTranscriptLivesBesideTheMainTranscript() throws {
    let data = try FixtureLoader.data("claude-bash-subagent")
    let request = try ClaudeAdapter.parse(data)
    let mainTranscriptPath = try #require(request.transcriptPath)
    let agentID = try #require(request.agentID)

    #expect(
      SubagentChainReader.transcriptPath(mainTranscriptPath: mainTranscriptPath, agentID: agentID)
        == "/Users/dev/.claude/projects/shop-api/b7e1c2a4-9f3d-4e2a-8c1b-5a6d7e8f9012/subagents/agent-a1b2c3d4.jsonl"
    )
  }

  @Test func anEmptyParentTranscriptNeverMatchesByAccident() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_unrelated")
    try fixture.writeEmptyAgentTranscript(agentID: "sibling")
    try fixture.writeMeta(
      agentID: "agent1", agentType: "general-purpose", description: "Orphaned",
      toolUseID: "toolu_root", spawnDepth: 2)

    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "agent1")
        == nil)
  }
}
