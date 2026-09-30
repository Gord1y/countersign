import Foundation

public struct SubagentChainLink: Sendable, Equatable {
  public var agentID: String
  public var agentType: String
  public var description: String

  public init(agentID: String, agentType: String, description: String) {
    self.agentID = agentID
    self.agentType = agentType
    self.description = description
  }
}

public enum SubagentChainReader {
  static let maxDepth = 10

  public static func chain(transcriptPath: String, agentID: String) -> [SubagentChainLink]? {
    let sessionDirectory = URL(
      fileURLWithPath: (transcriptPath as NSString).deletingPathExtension)
    let subagentsDirectory = sessionDirectory.appendingPathComponent("subagents")
    let mainTranscriptURL = URL(fileURLWithPath: transcriptPath)

    var links: [SubagentChainLink] = []
    var visited: Set<String> = []
    var currentAgentID: String? = agentID

    while let agentID = currentAgentID {
      guard links.count < maxDepth else { return nil }
      guard visited.insert(agentID).inserted else { return nil }
      guard let meta = readMeta(agentID: agentID, subagentsDirectory: subagentsDirectory) else {
        return nil
      }
      links.append(
        SubagentChainLink(
          agentID: agentID, agentType: meta.agentType, description: meta.description))

      if let parentAgentID = meta.parentAgentID {
        currentAgentID = parentAgentID
      } else if meta.spawnDepth == 1 {
        currentAgentID = nil
      } else if containsToolUseID(meta.toolUseID, in: mainTranscriptURL) {
        currentAgentID = nil
      } else if let parentAgentID = findParentAgentID(
        toolUseID: meta.toolUseID, subagentsDirectory: subagentsDirectory, excluding: agentID)
      {
        currentAgentID = parentAgentID
      } else {
        return nil
      }
    }

    return links.reversed()
  }

  private struct SubagentMeta {
    let agentType: String
    let description: String
    let toolUseID: String
    let parentAgentID: String?
    let spawnDepth: Int?
  }

  private static func readMeta(agentID: String, subagentsDirectory: URL) -> SubagentMeta? {
    let url = subagentsDirectory.appendingPathComponent("agent-\(agentID).meta.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
    guard let agentType = value["agentType"]?.stringValue,
      let description = value["description"]?.stringValue,
      let toolUseID = value["toolUseId"]?.stringValue
    else { return nil }
    return SubagentMeta(
      agentType: agentType, description: description, toolUseID: toolUseID,
      parentAgentID: value["parentAgentId"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 },
      spawnDepth: spawnDepth(from: value["spawnDepth"]))
  }

  private static func spawnDepth(from value: JSONValue?) -> Int? {
    switch value {
    case .int(let depth): return Int(exactly: depth)
    case .double(let depth): return Int(exactly: depth)
    default: return nil
    }
  }

  private static func containsToolUseID(_ toolUseID: String, in url: URL) -> Bool {
    guard let data = try? Data(contentsOf: url) else { return false }
    guard let needle = toolUseID.data(using: .utf8), !needle.isEmpty else { return false }
    return data.range(of: needle) != nil
  }

  private static func findParentAgentID(
    toolUseID: String, subagentsDirectory: URL, excluding agentID: String
  ) -> String? {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: subagentsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return nil }
    let excludedName = "agent-\(agentID).jsonl"
    for entry in entries {
      guard entry.pathExtension == "jsonl", entry.lastPathComponent != excludedName else {
        continue
      }
      guard let candidateID = self.agentID(fromTranscriptFilename: entry.lastPathComponent)
      else { continue }
      if containsToolUseID(toolUseID, in: entry) {
        return candidateID
      }
    }
    return nil
  }

  private static func agentID(fromTranscriptFilename filename: String) -> String? {
    let prefix = "agent-"
    let suffix = ".jsonl"
    guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else { return nil }
    let start = filename.index(filename.startIndex, offsetBy: prefix.count)
    let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
    guard start < end else { return nil }
    return String(filename[start..<end])
  }
}
