import Foundation

public enum ShellCommandSegments {
  public static func split(_ command: String) -> [String]? {
    let scalars = Array(command.unicodeScalars)
    var segments: [String] = []
    var current = String.UnicodeScalarView()
    var inSingleQuote = false
    var inDoubleQuote = false
    var index = 0

    func scalar(at position: Int) -> Unicode.Scalar? {
      position >= 0 && position < scalars.count ? scalars[position] : nil
    }

    func endSegment() {
      segments.append(String(current))
      current = String.UnicodeScalarView()
    }

    func startsWord(at position: Int) -> Bool {
      guard let previous = scalar(at: position - 1) else { return true }
      return " \t\n;&|<>".unicodeScalars.contains(previous)
    }

    func endsWord(at position: Int) -> Bool {
      guard let following = scalar(at: position) else { return true }
      return " \t\n;&|<>()".unicodeScalars.contains(following)
    }

    func endOfHarmlessOutput(at position: Int) -> Int? {
      var cursor = position + 1
      if scalar(at: cursor) == ">" || scalar(at: cursor) == "|" { cursor += 1 }
      if scalar(at: cursor) == "&" {
        cursor += 1
        let digitsStart = cursor
        while let digit = scalar(at: cursor), ("0"..."9").contains(digit) { cursor += 1 }
        return cursor > digitsStart && endsWord(at: cursor) ? cursor : nil
      }
      while scalar(at: cursor) == " " || scalar(at: cursor) == "\t" { cursor += 1 }
      let targetStart = cursor
      while !endsWord(at: cursor) { cursor += 1 }
      let target = String(String.UnicodeScalarView(scalars[targetStart..<cursor]))
      return target == "/dev/null" ? cursor : nil
    }

    while index < scalars.count {
      let character = scalars[index]
      let next = scalar(at: index + 1)

      if inSingleQuote {
        current.append(character)
        if character == "'" { inSingleQuote = false }
        index += 1
        continue
      }

      if inDoubleQuote {
        if character == "\\" {
          current.append(character)
          if let next { current.append(next) }
          index += 2
          continue
        }
        if character == "`" || character == "$" { return nil }
        current.append(character)
        if character == "\"" { inDoubleQuote = false }
        index += 1
        continue
      }

      switch character {
      case "\\":
        current.append(character)
        if let next { current.append(next) }
        index += 2
      case "'":
        inSingleQuote = true
        current.append(character)
        index += 1
      case "\"":
        inDoubleQuote = true
        current.append(character)
        index += 1
      case "`", "(", ")", "{", "}", "$":
        return nil
      case "#":
        if startsWord(at: index) { return nil }
        current.append(character)
        index += 1
      case "<":
        if next == "(" || next == ">" { return nil }
        current.append(character)
        index += 1
      case ">":
        guard next != "(", let end = endOfHarmlessOutput(at: index) else { return nil }
        current.append(contentsOf: scalars[index..<end])
        index = end
      case ";", "\n":
        endSegment()
        index += 1
      case "|":
        endSegment()
        index += next == "|" || next == "&" ? 2 : 1
      case "&":
        if next == "&" {
          endSegment()
          index += 2
        } else if scalar(at: index - 1) == ">" || scalar(at: index - 1) == "<" || next == ">" {
          current.append(character)
          index += 1
        } else {
          endSegment()
          index += 1
        }
      default:
        current.append(character)
        index += 1
      }
    }

    if inSingleQuote || inDoubleQuote { return nil }
    endSegment()
    return
      segments
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}
