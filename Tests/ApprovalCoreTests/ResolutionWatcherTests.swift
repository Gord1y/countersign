import Foundation
import Testing

@testable import ApprovalCore

private final class MutablePID {
  var value: Int32
  init(_ value: Int32) { self.value = value }
}

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func makeRequest(
  host: ApprovalCore.Host = .claude,
  sessionID: String = "session-1",
  toolName: String = "Bash",
  toolInput: JSONValue = .object(["command": .string("ls -la")]),
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
    toolName: toolName,
    toolInput: toolInput,
    kind: .permission(PermissionPrompt(body: .json(toolInput), suggestions: []))
  )
}

private func writeRegistryFile(
  at url: URL,
  sessionID: String,
  status: String?,
  pid: Int64 = 48213
) throws {
  var object: [String: JSONValue] = ["pid": .int(pid), "sessionId": .string(sessionID)]
  if let status {
    object["status"] = .string(status)
  }
  let data = try JSONEncoder().encode(JSONValue.object(object))
  try data.write(to: url)
}

private func setModificationDate(_ date: Date, on url: URL) throws {
  try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

private func toolUseValue(id: String, name: String, input: [String: JSONValue]) -> JSONValue {
  .object([
    "type": .string("assistant"),
    "uuid": .string("assistant-\(id)"),
    "message": .object([
      "role": .string("assistant"),
      "content": .array([
        .object([
          "type": .string("tool_use"),
          "id": .string(id),
          "name": .string(name),
          "input": .object(input),
        ])
      ]),
    ]),
  ])
}

private func toolResultValue(id: String) -> JSONValue {
  .object([
    "type": .string("user"),
    "uuid": .string("result-\(id)"),
    "message": .object([
      "role": .string("user"),
      "content": .array([
        .object([
          "type": .string("tool_result"),
          "tool_use_id": .string(id),
          "content": .string("ok"),
        ])
      ]),
    ]),
  ])
}

private func encodeLine(_ value: JSONValue) throws -> String {
  let data = try JSONEncoder().encode(value)
  return String(decoding: data, as: UTF8.self)
}

private func writeTranscript(_ url: URL, lines: [JSONValue]) throws {
  var text = ""
  for line in lines {
    text += try encodeLine(line) + "\n"
  }
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data(text.utf8).write(to: url)
}

private func appendTranscript(_ url: URL, lines: [JSONValue]) throws {
  var text = ""
  for line in lines {
    text += try encodeLine(line) + "\n"
  }
  try appendRaw(url, text)
}

private func appendRaw(_ url: URL, _ content: String) throws {
  if !FileManager.default.fileExists(atPath: url.path) {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: nil)
  }
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  try handle.seekToEnd()
  try handle.write(contentsOf: Data(content.utf8))
}

@Suite struct ResolutionWatcherTests {

  @Test func registryBusyWaitingBusyFiresOnThirdPoll() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "s1")
    let registryURL = dir.appendingPathComponent("100.json")
    try writeRegistryFile(at: registryURL, sessionID: "s1", status: "busy")
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "s1", status: "waiting")
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "s1", status: "busy")
    #expect(watcher.poll() == .registry)
  }

  @Test func registryIdleBusyIdleNeverFires() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "s2")
    let registryURL = dir.appendingPathComponent("101.json")
    try writeRegistryFile(at: registryURL, sessionID: "s2", status: "idle")
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "s2", status: "busy")
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "s2", status: "idle")
    #expect(watcher.poll() == nil)
  }

  @Test func registryWaitingWaitingDoesNotFire() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "s3")
    let registryURL = dir.appendingPathComponent("102.json")
    try writeRegistryFile(at: registryURL, sessionID: "s3", status: "waiting")
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    #expect(watcher.poll() == nil)
  }

  @Test func registryAnotherSessionsFileNeverFires() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "mine")
    let registryURL = dir.appendingPathComponent("103.json")
    try writeRegistryFile(at: registryURL, sessionID: "other", status: "busy")
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "other", status: "waiting")
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "other", status: "busy")
    #expect(watcher.poll() == nil)
  }

  @Test func registryKeyFileIsNeverReadEvenWhenItWouldMatch() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "s4")
    let keyURL = dir.appendingPathComponent("104.key")
    try writeRegistryFile(at: keyURL, sessionID: "s4", status: "waiting")
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: keyURL, sessionID: "s4", status: "busy")
    #expect(watcher.poll() == nil)
  }

  @Test func registryTruncatedJSONIsNoSignalAndDoesNotCrash() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "s5")
    let registryURL = dir.appendingPathComponent("105.json")
    try Data("{\"pid\":48213,\"sessionId\":\"s5\",\"stat".utf8).write(to: registryURL)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    #expect(watcher.poll() == nil)
  }

  @Test func registryNewerModificationDateWins() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "s6")
    let olderURL = dir.appendingPathComponent("200.json")
    let newerURL = dir.appendingPathComponent("201.json")
    try writeRegistryFile(at: olderURL, sessionID: "s6", status: "idle")
    try setModificationDate(Date(timeIntervalSince1970: 1000), on: olderURL)
    try writeRegistryFile(at: newerURL, sessionID: "s6", status: "waiting")
    try setModificationDate(Date(timeIntervalSince1970: 2000), on: newerURL)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: newerURL, sessionID: "s6", status: "busy")
    #expect(watcher.poll() == .registry)
  }

  @Test func transcriptIdenticalOlderCallWithResultAlreadyPresentNeverFires() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    try writeTranscript(
      transcriptURL,
      lines: [
        toolUseValue(id: "toolu_1", name: "Bash", input: input),
        toolResultValue(id: "toolu_1"),
      ])
    let request = makeRequest(
      sessionID: "t1", toolInput: .object(input), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    #expect(watcher.poll() == nil)
  }

  @Test func transcriptPendingToolUseFollowedByAppendedResultFires() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    try writeTranscript(
      transcriptURL, lines: [toolUseValue(id: "toolu_2", name: "Bash", input: input)])
    let request = makeRequest(
      sessionID: "t2", toolInput: .object(input), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try appendTranscript(transcriptURL, lines: [toolResultValue(id: "toolu_2")])
    #expect(watcher.poll() == .transcript)
  }

  @Test func transcriptToolUseAppendedAfterFirstPollThenResultFires() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    try writeTranscript(transcriptURL, lines: [])
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    let request = makeRequest(
      sessionID: "t3", toolInput: .object(input), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try appendTranscript(
      transcriptURL, lines: [toolUseValue(id: "toolu_3", name: "Bash", input: input)])
    #expect(watcher.poll() == nil)
    try appendTranscript(transcriptURL, lines: [toolResultValue(id: "toolu_3")])
    #expect(watcher.poll() == .transcript)
  }

  @Test func transcriptToolUseAndResultAppendedInOneBatchFires() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    try writeTranscript(transcriptURL, lines: [])
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    let request = makeRequest(
      sessionID: "t4", toolInput: .object(input), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try appendTranscript(
      transcriptURL,
      lines: [
        toolUseValue(id: "toolu_4", name: "Bash", input: input),
        toolResultValue(id: "toolu_4"),
      ])
    #expect(watcher.poll() == .transcript)
  }

  @Test func transcriptResultForNonMatchingToolUseDoesNotFire() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    try writeTranscript(transcriptURL, lines: [])
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    let request = makeRequest(
      sessionID: "t5", toolInput: .object(input), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try appendTranscript(
      transcriptURL,
      lines: [toolUseValue(id: "toolu_5", name: "Write", input: ["file_path": .string("x")])])
    #expect(watcher.poll() == nil)
    try appendTranscript(transcriptURL, lines: [toolResultValue(id: "toolu_5")])
    #expect(watcher.poll() == nil)
  }

  @Test func transcriptExtraKeyInInputStillMatches() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    try writeTranscript(transcriptURL, lines: [])
    let requestInput: [String: JSONValue] = ["command": .string("ls -la")]
    let echoedInput: [String: JSONValue] = [
      "command": .string("ls -la"), "timeout": .int(120_000),
    ]
    let request = makeRequest(
      sessionID: "t6", toolInput: .object(requestInput), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try appendTranscript(
      transcriptURL, lines: [toolUseValue(id: "toolu_6", name: "Bash", input: echoedInput)])
    #expect(watcher.poll() == nil)
    try appendTranscript(transcriptURL, lines: [toolResultValue(id: "toolu_6")])
    #expect(watcher.poll() == .transcript)
  }

  @Test func transcriptPartialLineIsProcessedOnceWhenCompleted() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    try writeTranscript(transcriptURL, lines: [])
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    let request = makeRequest(
      sessionID: "t7", toolInput: .object(input), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    let line = try encodeLine(toolUseValue(id: "toolu_7", name: "Bash", input: input))
    try appendRaw(transcriptURL, line)
    #expect(watcher.poll() == nil)
    try appendRaw(transcriptURL, "\n")
    #expect(watcher.poll() == nil)
    try appendTranscript(transcriptURL, lines: [toolResultValue(id: "toolu_7")])
    #expect(watcher.poll() == .transcript)
  }

  @Test func transcriptSubagentPathIsReadAndMainFileIsIgnored() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let mainURL = dir.appendingPathComponent("transcript.jsonl")
    let subagentURL =
      dir
      .appendingPathComponent("transcript")
      .appendingPathComponent("subagents")
      .appendingPathComponent("agent-a1b2.jsonl")
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    try writeTranscript(
      mainURL, lines: [toolUseValue(id: "main_toolu", name: "Bash", input: input)])
    try writeTranscript(
      subagentURL,
      lines: [
        toolUseValue(id: "sub_toolu", name: "Bash", input: input),
        toolResultValue(id: "sub_toolu"),
      ])
    let request = makeRequest(
      sessionID: "t8", toolInput: .object(input), transcriptPath: mainURL.path, agentID: "a1b2")
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try appendTranscript(mainURL, lines: [toolResultValue(id: "main_toolu")])
    #expect(watcher.poll() == nil)
    try appendTranscript(
      subagentURL, lines: [toolUseValue(id: "sub_toolu2", name: "Bash", input: input)])
    #expect(watcher.poll() == nil)
    try appendTranscript(subagentURL, lines: [toolResultValue(id: "sub_toolu2")])
    #expect(watcher.poll() == .transcript)
  }

  @Test func transcriptFileTruncationResetsWithoutCrashing() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript.jsonl")
    let input: [String: JSONValue] = ["command": .string("ls -la")]
    try writeTranscript(
      transcriptURL,
      lines: [
        toolUseValue(id: "toolu_a", name: "Bash", input: input),
        toolResultValue(id: "toolu_a"),
        toolUseValue(id: "toolu_filler", name: "Bash", input: input),
        toolResultValue(id: "toolu_filler"),
      ])
    let request = makeRequest(
      sessionID: "t9", toolInput: .object(input), transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try writeTranscript(
      transcriptURL, lines: [toolUseValue(id: "toolu_b", name: "Bash", input: input)])
    #expect(watcher.poll() == nil)
    try appendTranscript(transcriptURL, lines: [toolResultValue(id: "toolu_b")])
    #expect(watcher.poll() == .transcript)
  }

  @Test func transcriptMissingFileIsNoSignal() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("missing.jsonl")
    let request = makeRequest(
      sessionID: "t10",
      toolInput: .object(["command": .string("ls -la")]),
      transcriptPath: transcriptURL.path)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    #expect(watcher.poll() == nil)
  }

  @Test func parentExitFires() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "p1")
    let pid = MutablePID(111)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { pid.value })
    #expect(watcher.poll() == nil)
    pid.value = 222
    #expect(watcher.poll() == .parentExited)
  }

  @Test func codexRequestIgnoresRegistryTransitions() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(host: .codex, sessionID: "c1", transcriptPath: nil)
    let registryURL = dir.appendingPathComponent("300.json")
    try writeRegistryFile(at: registryURL, sessionID: "c1", status: "waiting")
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { 1 })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "c1", status: "busy")
    #expect(watcher.poll() == nil)
  }

  @Test func cursorRequestWatchesOnlyItsParent() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("chat.jsonl")
    try Data("{}\n".utf8).write(to: transcriptURL)
    let request = makeRequest(host: .cursor, sessionID: "u1", transcriptPath: transcriptURL.path)
    let registryURL = dir.appendingPathComponent("301.json")
    try writeRegistryFile(at: registryURL, sessionID: "u1", status: "waiting")
    let pid = MutablePID(111)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { pid.value })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "u1", status: "busy")
    #expect(watcher.poll() == nil)
    #expect(ResolutionWatcher.resolveTranscriptURL(for: request) == nil)
    pid.value = 222
    #expect(watcher.poll() == .parentExited)
  }

  @Test func antigravityRequestWatchesOnlyItsParent() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let transcriptURL = dir.appendingPathComponent("transcript_full.jsonl")
    try Data("{}\n".utf8).write(to: transcriptURL)
    let request = makeRequest(
      host: .antigravity, sessionID: "a1", transcriptPath: transcriptURL.path)
    let registryURL = dir.appendingPathComponent("302.json")
    try writeRegistryFile(at: registryURL, sessionID: "a1", status: "waiting")
    let pid = MutablePID(111)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { pid.value })
    #expect(watcher.poll() == nil)
    try writeRegistryFile(at: registryURL, sessionID: "a1", status: "busy")
    #expect(watcher.poll() == nil)
    #expect(ResolutionWatcher.resolveTranscriptURL(for: request) == nil)
    pid.value = 222
    #expect(watcher.poll() == .parentExited)
  }

  @Test func stickyReasonRepeatsAfterFiring() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let request = makeRequest(sessionID: "sticky")
    let pid = MutablePID(111)
    let watcher = ResolutionWatcher(
      request: request, sessionsDirectory: dir, parentPID: { pid.value })
    #expect(watcher.poll() == nil)
    pid.value = 222
    #expect(watcher.poll() == .parentExited)
    #expect(watcher.poll() == .parentExited)
    #expect(watcher.poll() == .parentExited)
  }
}
