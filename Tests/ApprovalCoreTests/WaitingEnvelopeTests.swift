import Foundation
import Testing

@testable import ApprovalCore

@Suite struct WaitingEnvelopeTests {
  @Test func readsClaudeStop() throws {
    let envelope = try #require(
      WaitingEnvelope.parse(FixtureLoader.data("claude-stop"), host: .claude))
    #expect(envelope.sessionID == "c4d2e8f1-7a3b-4c5d-9e6f-1a2b3c4d5e6f")
    #expect(envelope.projectPath == "/Users/dev/Projects/shop-api")
    #expect(envelope.projectName == "shop-api")
    #expect(
      envelope.transcriptPath
        == "/Users/dev/.claude/projects/shop-api/c4d2e8f1-7a3b-4c5d-9e6f-1a2b3c4d5e6f.jsonl")
  }

  @Test func readsCodexEnvelope() throws {
    let envelope = try #require(
      WaitingEnvelope.parse(FixtureLoader.data("codex-bash"), host: .codex))
    #expect(envelope.sessionID == "d9e0f1a2-8192-40a4-e567-89abcdef0123")
    #expect(envelope.projectPath == "/Users/dev/Projects/shop-api")
    #expect(envelope.transcriptPath == nil)
  }

  @Test func readsCursorEnvelope() throws {
    let envelope = try #require(
      WaitingEnvelope.parse(FixtureLoader.data("cursor-shell"), host: .cursor))
    #expect(envelope.sessionID == "c3d4e5f6-a1b2-4c3d-8e9f-0a1b2c3d4e5f")
    #expect(envelope.projectPath == "/Users/dev/Projects/shop-api")
    #expect(
      envelope.transcriptPath
        == "/Users/dev/.cursor/projects/Users-dev-Projects-shop-api/agent-transcripts/"
        + "c3d4e5f6-a1b2-4c3d-8e9f-0a1b2c3d4e5f/c3d4e5f6-a1b2-4c3d-8e9f-0a1b2c3d4e5f.jsonl")
  }

  @Test func readsAntigravityEnvelope() throws {
    let envelope = try #require(
      WaitingEnvelope.parse(FixtureLoader.data("antigravity-run-command"), host: .antigravity))
    #expect(envelope.sessionID == "e1f2a3b4-c5d6-4e7f-8a9b-0c1d2e3f4a5b")
    #expect(envelope.projectPath == "/Users/dev/Projects/shop-api")
    #expect(
      envelope.transcriptPath
        == "/Users/dev/.gemini/antigravity-cli/brain/e1f2a3b4-c5d6-4e7f-8a9b-0c1d2e3f4a5b/"
        + ".system_generated/logs/transcript_full.jsonl")
  }

  @Test func payloadWithoutSessionIDIsNil() throws {
    let decoded = try JSONDecoder().decode(
      JSONValue.self, from: FixtureLoader.data("claude-stop"))
    var root = try #require(decoded.objectValue)
    root["session_id"] = nil
    let withoutSession = try JSONEncoder().encode(JSONValue.object(root))
    #expect(WaitingEnvelope.parse(withoutSession, host: .claude) == nil)
    #expect(WaitingEnvelope.parse(Data("[]".utf8), host: .claude) == nil)
  }
}
