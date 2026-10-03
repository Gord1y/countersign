import Foundation

public struct CommandPattern: Sendable, Equatable {
  public let text: String

  public init(_ text: String) {
    self.text = text
  }

  public func matches(_ segment: String) -> Bool {
    let pattern = Self.trimmed(text)
    let command = Self.trimmed(segment)
    guard !pattern.isEmpty else { return false }
    if let colon = pattern.firstIndex(of: ":") {
      let base = String(pattern[..<colon])
      let glob = String(pattern[pattern.index(after: colon)...])
      return Self.matchesBaseAndArguments(command, base: base, glob: glob)
    }
    if command == pattern { return true }
    guard command.hasPrefix(pattern) else { return false }
    let following = command[command.index(command.startIndex, offsetBy: pattern.count)]
    return Self.isBlank(following)
  }

  public static func exact(forSegment segment: String) -> CommandPattern? {
    let command = trimmed(segment)
    guard !command.isEmpty else { return nil }
    guard command.contains(":") else { return CommandPattern(command) }
    guard !command.contains("*") else { return nil }
    let word = command.prefix(while: { !isBlank($0) })
    guard !word.contains(":") else { return nil }
    let arguments = String(command.dropFirst(word.count).drop(while: isBlank))
    return CommandPattern("\(word):\(arguments)")
  }

  public static func allMatch(_ command: String, patterns: [CommandPattern]) -> Bool {
    guard let segments = ShellCommandSegments.split(command), !segments.isEmpty else {
      return false
    }
    return segments.allSatisfy { segment in
      patterns.contains { $0.matches(segment) }
    }
  }

  private static func isBlank(_ character: Character) -> Bool {
    character == " " || character == "\t"
  }

  private static func trimmed(_ text: String) -> String {
    String(text.drop(while: isBlank).reversed().drop(while: isBlank).reversed())
  }

  private static func matchesBaseAndArguments(_ command: String, base: String, glob: String)
    -> Bool
  {
    let word = command.prefix(while: { !isBlank($0) })
    guard !word.isEmpty, String(word) == base else { return false }
    let arguments = String(command.dropFirst(word.count).drop(while: isBlank))
    return globMatches(Array(glob), Array(arguments))
  }

  static func globMatches(_ glob: [Character], _ text: [Character]) -> Bool {
    var globIndex = 0
    var textIndex = 0
    var starIndex: Int?
    var starTextIndex = 0
    while textIndex < text.count {
      if globIndex < glob.count, glob[globIndex] == "*" {
        starIndex = globIndex
        starTextIndex = textIndex
        globIndex += 1
      } else if globIndex < glob.count, glob[globIndex] == text[textIndex] {
        globIndex += 1
        textIndex += 1
      } else if let star = starIndex {
        globIndex = star + 1
        starTextIndex += 1
        textIndex = starTextIndex
      } else {
        return false
      }
    }
    while globIndex < glob.count, glob[globIndex] == "*" { globIndex += 1 }
    return globIndex == glob.count
  }
}
