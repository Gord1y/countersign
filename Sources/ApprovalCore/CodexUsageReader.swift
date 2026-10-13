import Foundation

public struct CodexContextReading: Sendable, Equatable {
  public var tokens: Int
  public var windowTokens: Int
  public var timestamp: Date?

  public init(tokens: Int, windowTokens: Int, timestamp: Date? = nil) {
    self.tokens = tokens
    self.windowTokens = windowTokens
    self.timestamp = timestamp
  }
}

public enum CodexUsageReader {
  public static func read(rolloutURL: URL) -> CodexContextReading? {
    guard let lines = ContextUsageReader.tailLines(ofFileAt: rolloutURL) else { return nil }
    return reading(fromLines: lines.map(String.init))
  }

  static func reading(fromLines lines: [String]) -> CodexContextReading? {
    for line in lines.reversed() {
      guard
        let row = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
        row.objectValue != nil,
        row["type"]?.stringValue == "event_msg",
        let payload = row["payload"],
        payload["type"]?.stringValue == "token_count",
        let info = payload["info"],
        let tokens = integer(info["last_token_usage"]?["input_tokens"]),
        let windowTokens = integer(info["model_context_window"]),
        windowTokens > 0
      else { continue }
      return CodexContextReading(
        tokens: tokens, windowTokens: windowTokens,
        timestamp: ContextUsageReader.timestamp(row["timestamp"]?.stringValue))
    }
    return nil
  }

  private static func integer(_ value: JSONValue?) -> Int? {
    guard case .int(let number) = value else { return nil }
    return Int(exactly: number)
  }
}
