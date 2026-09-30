import Foundation

public enum TranscriptGrowth {
  public static let settleSeconds = 10
  public static let maximumReadBytes = 1_048_576

  static let claudeResumingTypes: Set<String> = ["user", "assistant", "queue-operation"]

  public static func resumed(host: Host, appended: Data) -> Bool {
    guard host == .claude else { return !appended.isEmpty }
    let newline = UInt8(ascii: "\n")
    guard let lastNewline = appended.lastIndex(of: newline) else { return false }
    let completeLines = appended[appended.startIndex..<lastNewline].split(separator: newline)
    return completeLines.contains { line in
      guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(line)),
        let type = decoded["type"]?.stringValue
      else { return false }
      return claudeResumingTypes.contains(type)
    }
  }
}
