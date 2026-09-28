import Foundation
import Testing

@testable import ApprovalCore

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func writeRegistryFile(at url: URL, fields: [String: JSONValue]) throws {
  let data = try JSONEncoder().encode(JSONValue.object(fields))
  try data.write(to: url)
}

private func makeRequest(
  host: ApprovalCore.Host = .claude,
  sessionID: String = "session-1",
  transcriptPath: String? = nil,
  agentID: String? = nil
) -> ApprovalRequest {
  ApprovalRequest(
    host: host,
    sessionID: sessionID,
    cwd: "/tmp/project",
    permissionMode: "default",
    transcriptPath: transcriptPath,
    agentID: agentID,
    agentType: agentID == nil ? nil : "Explore",
    toolName: "Bash",
    toolInput: .object(["command": .string("ls")]),
    kind: .permission(PermissionPrompt(body: .json(.object([:])), suggestions: []))
  )
}

@Suite struct ChatTrackingHealthTests {
  @Test func healthyEntryWithReadableTranscriptHasNoDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    try Data("{}".utf8).write(to: transcriptURL)
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(
      at: registryURL, fields: ["sessionId": .string("s1"), "status": .string("idle")])
    let request = makeRequest(sessionID: "s1", transcriptPath: transcriptURL.path)
    #expect(ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == nil)
  }

  @Test func noRegistryEntryIsDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "s2")
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == .noRegistryEntry)
  }

  @Test func unparseableRegistryFileIsTreatedAsNoEntry() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryURL = dir.appendingPathComponent("100.json")
    try Data("{\"sessionId\":\"s3\"".utf8).write(to: registryURL)
    let request = makeRequest(sessionID: "s3")
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == .noRegistryEntry)
  }

  @Test func unknownStatusIsDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(
      at: registryURL, fields: ["sessionId": .string("s4"), "status": .string("weird")])
    let request = makeRequest(sessionID: "s4")
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir)
        == .unknownStatus("weird"))
  }

  @Test func missingStatusFieldIsDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(at: registryURL, fields: ["sessionId": .string("s5")])
    let request = makeRequest(sessionID: "s5")
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == .unknownStatus(nil))
  }

  @Test func missingTranscriptIsDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(
      at: registryURL, fields: ["sessionId": .string("s6"), "status": .string("busy")])
    let request = makeRequest(
      sessionID: "s6", transcriptPath: dir.appendingPathComponent("missing.jsonl").path)
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir)
        == .transcriptUnreadable)
  }

  @Test func noTranscriptPathAtAllIsDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(
      at: registryURL, fields: ["sessionId": .string("s7"), "status": .string("waiting")])
    let request = makeRequest(sessionID: "s7", transcriptPath: nil)
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir)
        == .transcriptUnreadable)
  }

  @Test func unreadableTranscriptDirectoryIsDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(
      at: registryURL, fields: ["sessionId": .string("s8"), "status": .string("idle")])
    let transcriptDirectory = dir.appendingPathComponent("not-a-file")
    try FileManager.default.createDirectory(
      at: transcriptDirectory, withIntermediateDirectories: true)
    let request = makeRequest(sessionID: "s8", transcriptPath: transcriptDirectory.path)
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir)
        == .transcriptUnreadable)
  }

  @Test func subagentTranscriptPathIsCheckedInstead() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(
      at: registryURL, fields: ["sessionId": .string("s9"), "status": .string("idle")])
    let mainTranscript = dir.appendingPathComponent("transcript.jsonl")
    try Data("{}".utf8).write(to: mainTranscript)
    let request = makeRequest(
      sessionID: "s9", transcriptPath: mainTranscript.path, agentID: "abcd")
    #expect(
      ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir)
        == .transcriptUnreadable)
    let subagentDirectory =
      dir
      .appendingPathComponent("transcript")
      .appendingPathComponent("subagents")
    try FileManager.default.createDirectory(
      at: subagentDirectory, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: subagentDirectory.appendingPathComponent("agent-abcd.jsonl"))
    #expect(ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == nil)
  }

  @Test func codexRequestsNeverReportDrift() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(host: .codex, sessionID: "c1", transcriptPath: nil)
    #expect(ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == nil)
  }

  @Test func evaluateTranscriptAloneIgnoresRegistry() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    try Data("{}".utf8).write(to: transcriptURL)
    let request = makeRequest(sessionID: "s10", transcriptPath: transcriptURL.path)
    #expect(ChatTrackingHealth.evaluateTranscript(request: request) == nil)
  }

  @Test func cursorRequestsNeverReportDriftEvenWithATranscriptPath() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(
      host: .cursor, sessionID: "u1", transcriptPath: dir.appendingPathComponent("gone.jsonl").path)
    #expect(ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == nil)
    #expect(ChatTrackingHealth.evaluateTranscript(request: request) == nil)
  }

  @Test func antigravityRequestsNeverReportDriftEvenWithATranscriptPath() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(
      host: .antigravity, sessionID: "a1",
      transcriptPath: dir.appendingPathComponent("gone.jsonl").path)
    #expect(ChatTrackingHealth.evaluate(request: request, sessionsDirectory: dir) == nil)
    #expect(ChatTrackingHealth.evaluateTranscript(request: request) == nil)
  }

  @Test func evaluateTranscriptAloneReturnsNilForCodex() {
    let request = makeRequest(host: .codex, sessionID: "c2", transcriptPath: nil)
    #expect(ChatTrackingHealth.evaluateTranscript(request: request) == nil)
  }
}
