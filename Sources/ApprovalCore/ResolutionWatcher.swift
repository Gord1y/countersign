import Foundation

public enum ResolutionReason: String, Sendable, Equatable {
  case registry
  case transcript
  case parentExited
}

public final class ResolutionWatcher {
  private let request: ApprovalRequest
  private let sessionsDirectory: URL
  private let parentPID: () -> Int32
  private let initialParentPID: Int32
  private let transcriptURL: URL?

  private var firedReason: ResolutionReason?

  private var cachedRegistryURL: URL?
  private var sawWaiting = false

  private var transcriptOffset: UInt64 = 0
  private var transcriptLineBuffer = Data()
  private var resultIDs: Set<String> = []
  private var pendingIDs: Set<String> = []
  private var hasCompletedInitialScan = false

  public init(
    request: ApprovalRequest,
    sessionsDirectory: URL,
    parentPID: @escaping () -> Int32 = { getppid() }
  ) {
    self.request = request
    self.sessionsDirectory = sessionsDirectory
    self.parentPID = parentPID
    self.initialParentPID = parentPID()
    self.transcriptURL = ResolutionWatcher.resolveTranscriptURL(for: request)
  }

  public func poll() -> ResolutionReason? {
    if let firedReason {
      return firedReason
    }
    if parentPID() != initialParentPID {
      firedReason = .parentExited
      return firedReason
    }
    guard request.host == .claude else {
      return nil
    }
    if pollRegistry() {
      firedReason = .registry
      return firedReason
    }
    if request.transcriptPath != nil, pollTranscript() {
      firedReason = .transcript
      return firedReason
    }
    return nil
  }

  static func resolveTranscriptURL(for request: ApprovalRequest) -> URL? {
    guard request.host == .claude, let transcriptPath = request.transcriptPath else {
      return nil
    }
    guard let agentID = request.agentID else {
      return URL(fileURLWithPath: transcriptPath)
    }
    let withoutExtension = (transcriptPath as NSString).deletingPathExtension
    return URL(fileURLWithPath: withoutExtension)
      .appendingPathComponent("subagents")
      .appendingPathComponent("agent-\(agentID).jsonl")
  }

  private func pollRegistry() -> Bool {
    if let cachedRegistryURL {
      guard let entry = ResolutionWatcher.readRegistryEntry(at: cachedRegistryURL),
        entry.sessionID == request.sessionID
      else {
        self.cachedRegistryURL = nil
        return pollRegistryAfterRescan()
      }
      return applyRegistryStatus(entry.status)
    }
    return pollRegistryAfterRescan()
  }

  private func pollRegistryAfterRescan() -> Bool {
    guard let foundURL = findRegistryEntry() else {
      return false
    }
    cachedRegistryURL = foundURL
    guard let entry = ResolutionWatcher.readRegistryEntry(at: foundURL),
      entry.sessionID == request.sessionID
    else {
      return false
    }
    return applyRegistryStatus(entry.status)
  }

  private func applyRegistryStatus(_ status: String?) -> Bool {
    guard let status else {
      return false
    }
    if status == "waiting" {
      sawWaiting = true
      return false
    }
    return sawWaiting
  }

  private func findRegistryEntry() -> URL? {
    SessionRegistry.findEntry(sessionID: request.sessionID, in: sessionsDirectory)?.url
  }

  private static func readRegistryEntry(at url: URL) -> (sessionID: String, status: String?)? {
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
      return nil
    }
    guard case .object(let object) = value else {
      return nil
    }
    guard let sessionID = object["sessionId"]?.stringValue else {
      return nil
    }
    return (sessionID, object["status"]?.stringValue)
  }

  private func pollTranscript() -> Bool {
    guard let transcriptURL else {
      return false
    }
    guard let handle = try? FileHandle(forReadingFrom: transcriptURL) else {
      return false
    }
    defer { try? handle.close() }
    guard let fileSize = try? handle.seekToEnd() else {
      return false
    }
    if fileSize < transcriptOffset {
      resetTranscriptState()
    }
    guard fileSize > transcriptOffset else {
      hasCompletedInitialScan = true
      return false
    }
    guard (try? handle.seek(toOffset: transcriptOffset)) != nil else {
      return false
    }
    guard let newData = try? handle.readToEnd() else {
      return false
    }
    transcriptOffset = fileSize
    var buffer = transcriptLineBuffer
    buffer.append(newData)

    let terminator = UInt8(ascii: "\n")
    let endsWithNewline = buffer.last == terminator
    let segments = buffer.split(separator: terminator, omittingEmptySubsequences: false)
    let completeLineCount = endsWithNewline ? segments.count : max(segments.count - 1, 0)
    let completeLines = segments.prefix(completeLineCount)
    transcriptLineBuffer = endsWithNewline ? Data() : (segments.last ?? Data())

    let wasInitialScan = !hasCompletedInitialScan
    if wasInitialScan {
      var matchingIDs: Set<String> = []
      for line in completeLines {
        processInitialLine(line, matchingIDs: &matchingIDs)
      }
      pendingIDs = matchingIDs.subtracting(resultIDs)
      hasCompletedInitialScan = true
      return false
    }

    var fired = false
    for line in completeLines {
      if processLaterLine(line) {
        fired = true
      }
    }
    return fired
  }

  private func resetTranscriptState() {
    transcriptOffset = 0
    transcriptLineBuffer = Data()
    resultIDs = []
    pendingIDs = []
    hasCompletedInitialScan = false
  }

  private func processInitialLine(_ line: Data, matchingIDs: inout Set<String>) {
    guard let blocks = ResolutionWatcher.transcriptBlocks(from: line) else {
      return
    }
    for block in blocks {
      switch block {
      case .toolUse(let id, let name, let input):
        if matches(name: name, input: input) {
          matchingIDs.insert(id)
        }
      case .toolResult(let toolUseID):
        resultIDs.insert(toolUseID)
      }
    }
  }

  private func processLaterLine(_ line: Data) -> Bool {
    guard let blocks = ResolutionWatcher.transcriptBlocks(from: line) else {
      return false
    }
    var fired = false
    for block in blocks {
      switch block {
      case .toolUse(let id, let name, let input):
        if matches(name: name, input: input), !resultIDs.contains(id) {
          pendingIDs.insert(id)
        }
      case .toolResult(let toolUseID):
        resultIDs.insert(toolUseID)
        if pendingIDs.contains(toolUseID) {
          fired = true
        }
      }
    }
    return fired
  }

  private enum TranscriptBlock {
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String)
  }

  private static func transcriptBlocks(from line: Data) -> [TranscriptBlock]? {
    guard !line.isEmpty else {
      return nil
    }
    let text = String(decoding: line, as: UTF8.self)
    guard text.contains("tool_use") || text.contains("tool_result") else {
      return nil
    }
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: line) else {
      return nil
    }
    guard let messageValue = value["message"], let content = messageValue["content"]?.arrayValue
    else {
      return nil
    }
    var blocks: [TranscriptBlock] = []
    for entry in content {
      guard case .object(let object) = entry, let type = object["type"]?.stringValue else {
        continue
      }
      switch type {
      case "tool_use":
        guard let id = object["id"]?.stringValue, let name = object["name"]?.stringValue else {
          continue
        }
        let input = object["input"] ?? .object([:])
        blocks.append(.toolUse(id: id, name: name, input: input))
      case "tool_result":
        guard let toolUseID = object["tool_use_id"]?.stringValue else {
          continue
        }
        blocks.append(.toolResult(toolUseID: toolUseID))
      default:
        continue
      }
    }
    return blocks
  }

  private func matches(name: String, input: JSONValue) -> Bool {
    guard name == request.toolName else {
      return false
    }
    guard case .object(let requestObject) = request.toolInput else {
      return input == request.toolInput
    }
    let stringKeys = requestObject.filter { key, value in
      if case .string = value { return true }
      return false
    }
    guard !stringKeys.isEmpty else {
      return input == request.toolInput
    }
    guard case .object(let inputObject) = input else {
      return false
    }
    for (key, value) in stringKeys {
      guard case .string(let expected) = value, inputObject[key]?.stringValue == expected else {
        return false
      }
    }
    return true
  }
}
