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

    return reading(fromLines: tailLines(from: tailData, startedMidFile: startOffset > 0))
  }

  public static func read(
    transcriptURL: URL, identity cached: ContextModelIdentity?, chunkBytes: Int = tailBytes
  ) -> (reading: ContextReading, identity: ContextModelIdentity)? {
    guard let handle = try? FileHandle(forReadingFrom: transcriptURL) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

    let usableCache = cached.flatMap { $0.scannedThrough <= size ? $0 : nil }
    let startOffset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
    guard (try? handle.seek(toOffset: startOffset)) != nil,
      let tailData = try? handle.readToEnd()
    else { return nil }

    let lines = tailLines(from: tailData, startedMidFile: startOffset > 0)
    if reading(fromLines: lines) != nil {
      var resolvedModelID = latestIdentityModelID(in: lines)
      if resolvedModelID == nil {
        let scanEnd =
          tailData.firstIndex(of: newline).map {
            startOffset + UInt64(tailData.distance(from: tailData.startIndex, to: $0)) + 1
          } ?? size
        resolvedModelID =
          scanBackwards(
            handle: handle, from: scanEnd, downTo: usableCache?.scannedThrough ?? 0,
            chunkBytes: max(chunkBytes, 1)) ?? usableCache?.modelID
      }
      guard let resolved = reading(fromLines: lines, identityFallback: resolvedModelID) else {
        return nil
      }
      return (resolved, ContextModelIdentity(modelID: resolvedModelID, scannedThrough: size))
    }
    guard startOffset > 0 else { return nil }

    guard (try? handle.seek(toOffset: 0)) != nil, let wholeData = try? handle.readToEnd() else {
      return nil
    }
    let wholeLines = tailLines(from: wholeData, startedMidFile: false)
    let wholeModelID = latestIdentityModelID(in: wholeLines) ?? usableCache?.modelID
    guard let wholeReading = reading(fromLines: wholeLines, identityFallback: wholeModelID) else {
      return nil
    }
    return (wholeReading, ContextModelIdentity(modelID: wholeModelID, scannedThrough: size))
  }

  private static let newline = UInt8(ascii: "\n")

  private static func latestIdentityModelID(in lines: [Substring]) -> String? {
    for line in lines.reversed() {
      guard let row = decodeRow(line), row["type"]?.stringValue == "attachment",
        let modelID = modelIdentity(of: row)
      else { continue }
      return modelID
    }
    return nil
  }

  private static func scanBackwards(
    handle: FileHandle, from scanEnd: UInt64, downTo floor: UInt64, chunkBytes: Int
  ) -> String? {
    var end = scanEnd
    var fragment = Data()
    while end > floor {
      let start = end - floor >= UInt64(chunkBytes) ? end - UInt64(chunkBytes) : floor
      guard (try? handle.seek(toOffset: start)) != nil,
        let chunk = try? handle.read(upToCount: Int(end - start))
      else { return nil }
      var data = chunk
      data.append(fragment)
      var completeData = data
      if start > floor {
        guard let firstNewline = data.firstIndex(of: newline) else {
          fragment = data
          end = start
          continue
        }
        fragment = Data(data[data.startIndex..<firstNewline])
        completeData = Data(data[data.index(after: firstNewline)...])
      }
      let lines = String(decoding: completeData, as: UTF8.self).split(
        separator: "\n", omittingEmptySubsequences: true)
      if let modelID = latestIdentityModelID(in: lines) {
        return modelID
      }
      end = start
    }
    return nil
  }

  static func reading(fromLines lines: [Substring], identityFallback: String? = nil)
    -> ContextReading?
  {
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
    var modelID = identityModelID ?? identityFallback
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
