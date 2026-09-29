import Foundation

public struct ContextReading: Sendable, Equatable {
  public var tokens: Int
  public var modelID: String?
  public var hasMillionTokenWindow: Bool
  public var compactionID: String?

  public init(tokens: Int, modelID: String?, hasMillionTokenWindow: Bool, compactionID: String?) {
    self.tokens = tokens
    self.modelID = modelID
    self.hasMillionTokenWindow = hasMillionTokenWindow
    self.compactionID = compactionID
  }
}

public enum ContextUsageReader {
  public static let tailBytes = 524_288
  public static let standardWindowTokens = 200_000
  static let millionTokenMarker = "[1m]"

  public static func read(transcriptURL: URL) -> ContextReading? {
    guard let handle = try? FileHandle(forReadingFrom: transcriptURL) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

    let startOffset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
    guard (try? handle.seek(toOffset: startOffset)) != nil,
      let tailData = try? handle.readToEnd()
    else { return nil }

    if let reading = reading(fromLines: tailLines(from: tailData, startedMidFile: startOffset > 0))
    {
      return reading
    }
    guard startOffset > 0 else { return nil }

    guard (try? handle.seek(toOffset: 0)) != nil, let wholeData = try? handle.readToEnd() else {
      return nil
    }
    return reading(fromLines: tailLines(from: wholeData, startedMidFile: false))
  }

  static func reading(fromLines lines: [Substring]) -> ContextReading? {
    var identityModelID: String?
    var compactionID: String?
    var sawBoundary = false
    var boundaryPostTokens: Int?
    var boundaryFollowsUsage = false
    var usage: (tokens: Int, modelID: String?)?

    for line in lines.reversed() {
      guard let row = decodeRow(line) else { continue }
      switch row["type"]?.stringValue {
      case "attachment":
        if identityModelID == nil, let modelID = modelIdentity(of: row) {
          identityModelID = modelID
        }
      case "system":
        guard row["subtype"]?.stringValue == "compact_boundary", !sawBoundary else { continue }
        sawBoundary = true
        compactionID = row["uuid"]?.stringValue
        boundaryPostTokens = integer(row["compactMetadata"]?["postTokens"])
        boundaryFollowsUsage = usage == nil
      case "assistant":
        guard usage == nil, row["isSidechain"]?.boolValue != true,
          let tokens = contextTokens(of: row)
        else { continue }
        usage = (tokens, row["message"]?["model"]?.stringValue)
      default:
        continue
      }
    }

    let tokens: Int
    var modelID = identityModelID
    if sawBoundary, boundaryFollowsUsage, let postTokens = boundaryPostTokens {
      tokens = postTokens
    } else if let usage {
      tokens = usage.tokens
      modelID = modelID ?? usage.modelID
    } else {
      return nil
    }

    let hasMillionTokenWindow =
      modelID?.contains(millionTokenMarker) == true || tokens > standardWindowTokens
    return ContextReading(
      tokens: tokens, modelID: modelID, hasMillionTokenWindow: hasMillionTokenWindow,
      compactionID: compactionID)
  }

  private static func tailLines(from data: Data, startedMidFile: Bool) -> [Substring] {
    let text = String(decoding: data, as: UTF8.self)
    var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    if startedMidFile {
      if let firstNewline = text.firstIndex(of: "\n") {
        lines = text[text.index(after: firstNewline)...].split(
          separator: "\n", omittingEmptySubsequences: true)
      } else {
        lines = []
      }
    }
    return lines
  }

  private static func decodeRow(_ line: Substring) -> JSONValue? {
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
      value.objectValue != nil
    else { return nil }
    return value
  }

  private static func modelIdentity(of row: JSONValue) -> String? {
    guard row["attachment"]?["type"]?.stringValue == "model" else { return nil }
    return row["attachment"]?["identity"]?["modelId"]?.stringValue
  }

  private static func integer(_ value: JSONValue?) -> Int? {
    guard case .int(let number) = value else { return nil }
    return Int(exactly: number)
  }

  private static func contextTokens(of row: JSONValue) -> Int? {
    guard let usage = row["message"]?["usage"], usage.objectValue != nil else { return nil }
    var total = 0
    var sawField = false
    for key in ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"] {
      guard let field = usage[key] else { continue }
      guard let number = integer(field) else { return nil }
      total += number
      sawField = true
    }
    return sawField ? total : nil
  }
}
