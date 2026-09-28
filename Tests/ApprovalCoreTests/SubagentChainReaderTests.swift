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
      toolUseID: "toolu_root", spawnDepth: 1)

    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "agent1")
        == nil)
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

  @Test func anEmptyParentTranscriptNeverMatchesByAccident() throws {
    let fixture = try ChainFixture()
    defer { fixture.remove() }

    try fixture.writeMainTranscript(spawning: "toolu_unrelated")
    try fixture.writeEmptyAgentTranscript(agentID: "sibling")
    try fixture.writeMeta(
      agentID: "agent1", agentType: "general-purpose", description: "Orphaned",
      toolUseID: "toolu_root", spawnDepth: 1)

    #expect(
      SubagentChainReader.chain(transcriptPath: fixture.transcriptPath, agentID: "agent1")
        == nil)
  }
}
