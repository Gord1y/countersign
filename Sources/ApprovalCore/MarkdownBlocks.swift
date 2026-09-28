import Foundation

public enum MarkdownBlock: Sendable, Equatable {
  case heading(level: Int, text: String)
  case bullet(indent: Int, text: String)
  case numbered(indent: Int, number: String, text: String)
  case code(language: String?, text: String)
  case rule
  case paragraph(text: String)
}

public enum MarkdownBlocks {
  public static func parse(_ markdown: String) -> [MarkdownBlock] {
    let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var blocks: [MarkdownBlock] = []
    var paragraphLines: [String] = []

    func flushParagraph() {
      guard !paragraphLines.isEmpty else { return }
      blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
      paragraphLines = []
    }

    var index = 0
    while index < lines.count {
      let line = lines[index]

      if isFenceLine(line) {
        flushParagraph()
        let language = fenceLanguage(line)
        index += 1
        var codeLines: [String] = []
        while index < lines.count, !isFenceLine(lines[index]) {
          codeLines.append(lines[index])
          index += 1
        }
        if index < lines.count {
          index += 1
        }
        blocks.append(.code(language: language, text: codeLines.joined(separator: "\n")))
        continue
      }

      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        flushParagraph()
        index += 1
        continue
      }

      if isRuleLine(trimmed) {
        flushParagraph()
        blocks.append(.rule)
        index += 1
        continue
      }

      if let heading = parseHeading(line) {
        flushParagraph()
        blocks.append(heading)
        index += 1
        continue
      }

      if let bullet = parseBullet(line) {
        flushParagraph()
        blocks.append(bullet)
        index += 1
        continue
      }

      if let numbered = parseNumbered(line) {
        flushParagraph()
        blocks.append(numbered)
        index += 1
        continue
      }

      paragraphLines.append(line)
      index += 1
    }

    flushParagraph()
    return blocks
  }

  private static func isFenceLine(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
  }

  private static func fenceLanguage(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let rest = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
    return rest.isEmpty ? nil : rest
  }

  private static func isRuleLine(_ trimmed: String) -> Bool {
    trimmed == "---" || trimmed == "***" || trimmed == "___"
  }

  private static func parseHeading(_ line: String) -> MarkdownBlock? {
    var count = 0
    for character in line {
      if character == "#" {
        count += 1
      } else {
        break
      }
    }
    guard (1...6).contains(count) else { return nil }
    let rest = line.dropFirst(count)
    guard rest.hasPrefix(" ") else { return nil }
    let text = rest.dropFirst().trimmingCharacters(in: .whitespaces)
    return .heading(level: count, text: text)
  }

  private static func parseBullet(_ line: String) -> MarkdownBlock? {
    let leadingSpaces = line.prefix(while: { $0 == " " }).count
    let rest = line.dropFirst(leadingSpaces)
    guard let marker = rest.first, marker == "-" || marker == "*" || marker == "+" else {
      return nil
    }
    let afterMarker = rest.dropFirst()
    guard afterMarker.hasPrefix(" ") else { return nil }
    let text = afterMarker.dropFirst().trimmingCharacters(in: .whitespaces)
    return .bullet(indent: leadingSpaces / 2, text: text)
  }

  private static func parseNumbered(_ line: String) -> MarkdownBlock? {
    let leadingSpaces = line.prefix(while: { $0 == " " }).count
    let rest = line.dropFirst(leadingSpaces)
    let digits = rest.prefix(while: { $0.isNumber })
    guard !digits.isEmpty else { return nil }
    let afterDigits = rest.dropFirst(digits.count)
    guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else {
      return nil
    }
    let afterDelimiter = afterDigits.dropFirst()
    guard afterDelimiter.hasPrefix(" ") else { return nil }
    let text = afterDelimiter.dropFirst().trimmingCharacters(in: .whitespaces)
    return .numbered(indent: leadingSpaces / 2, number: String(digits), text: text)
  }
}
