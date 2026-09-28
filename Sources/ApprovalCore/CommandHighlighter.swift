import Foundation

public enum ShellTokenKind: Sendable, Equatable {
  case command
  case flag
  case string
  case variable
  case `operator`
  case comment
}

public struct ShellToken: Sendable, Equatable {
  public let kind: ShellTokenKind
  public let range: Range<String.Index>

  public init(kind: ShellTokenKind, range: Range<String.Index>) {
    self.kind = kind
    self.range = range
  }
}

public enum CommandHighlighter {
  public static func tokens(in command: String) -> [ShellToken] {
    var tokens: [ShellToken] = []
    var index = command.startIndex
    let end = command.endIndex
    var expectCommand = true

    while index < end {
      let ch = command[index]

      if ch.isWhitespace {
        if ch == "\n" {
          expectCommand = true
        }
        index = command.index(after: index)
        continue
      }

      if ch == "#" {
        let newlineIndex = command[index...].firstIndex(of: "\n") ?? end
        tokens.append(ShellToken(kind: .comment, range: index..<newlineIndex))
        index = newlineIndex
        continue
      }

      if ch == "'" {
        let stringEnd = singleQuotedStringEnd(command, from: index, end: end)
        tokens.append(ShellToken(kind: .string, range: index..<stringEnd))
        index = stringEnd
        expectCommand = false
        continue
      }

      if ch == "\"" {
        let stringEnd = doubleQuotedStringEnd(command, from: index, end: end)
        tokens.append(ShellToken(kind: .string, range: index..<stringEnd))
        index = stringEnd
        expectCommand = false
        continue
      }

      if let match = matchOperator(command, at: index, end: end) {
        tokens.append(ShellToken(kind: .operator, range: index..<match.end))
        index = match.end
        if match.startsCommand {
          expectCommand = true
        }
        continue
      }

      if ch == "$", let variableEnd = matchVariable(command, at: index, end: end) {
        tokens.append(ShellToken(kind: .variable, range: index..<variableEnd))
        index = variableEnd
        expectCommand = false
        continue
      }

      let wordEnd = plainWordEnd(command, from: index, end: end)
      if wordEnd == index {
        index = command.index(after: index)
        continue
      }
      let word = String(command[index..<wordEnd])
      if expectCommand {
        if isAssignment(word) {
        } else {
          tokens.append(ShellToken(kind: .command, range: index..<wordEnd))
          expectCommand = false
        }
      } else if word.hasPrefix("-") {
        tokens.append(ShellToken(kind: .flag, range: index..<wordEnd))
      }
      index = wordEnd
    }

    return tokens
  }

  private static func singleQuotedStringEnd(
    _ command: String, from start: String.Index, end: String.Index
  ) -> String.Index {
    var index = command.index(after: start)
    while index < end, command[index] != "'" {
      index = command.index(after: index)
    }
    return index < end ? command.index(after: index) : end
  }

  private static func doubleQuotedStringEnd(
    _ command: String, from start: String.Index, end: String.Index
  ) -> String.Index {
    var index = command.index(after: start)
    while index < end {
      if command[index] == "\\" {
        index = command.index(after: index)
        if index < end {
          index = command.index(after: index)
        }
        continue
      }
      if command[index] == "\"" {
        break
      }
      index = command.index(after: index)
    }
    return index < end ? command.index(after: index) : end
  }

  private static let commandStartingOperators: Set<String> = ["|", "||", "&&", ";", "&", "(", "$("]

  private static func matchOperator(
    _ command: String, at index: String.Index, end: String.Index
  ) -> (end: String.Index, startsCommand: Bool)? {
    if let digitRedirectEnd = matchDigitRedirect(command, at: index, end: end) {
      return (digitRedirectEnd, false)
    }
    let staticOperators = ["&&", "||", ">>", "&>", "$(", "|", ";", "&", ">", "<", "(", ")"]
    for op in staticOperators where command[index...].hasPrefix(op) {
      let opEnd = command.index(index, offsetBy: op.count)
      return (opEnd, commandStartingOperators.contains(op))
    }
    return nil
  }

  private static func matchDigitRedirect(
    _ command: String, at index: String.Index, end: String.Index
  ) -> String.Index? {
    guard command[index].isNumber else { return nil }
    var digitsEnd = index
    while digitsEnd < end, command[digitsEnd].isNumber {
      digitsEnd = command.index(after: digitsEnd)
    }
    guard digitsEnd < end, command[digitsEnd] == ">" else { return nil }
    let afterAngle = command.index(after: digitsEnd)
    guard afterAngle < end, command[afterAngle] == "&" else { return afterAngle }
    let afterAmpersand = command.index(after: afterAngle)
    guard afterAmpersand < end, command[afterAmpersand].isNumber else { return afterAngle }
    var fdEnd = afterAmpersand
    while fdEnd < end, command[fdEnd].isNumber {
      fdEnd = command.index(after: fdEnd)
    }
    return fdEnd
  }

  private static func matchVariable(
    _ command: String, at index: String.Index, end: String.Index
  ) -> String.Index? {
    let afterDollar = command.index(after: index)
    guard afterDollar < end else { return nil }
    let ch = command[afterDollar]

    if ch == "{" {
      var braceEnd = command.index(after: afterDollar)
      while braceEnd < end, command[braceEnd] != "}" {
        braceEnd = command.index(after: braceEnd)
      }
      return braceEnd < end ? command.index(after: braceEnd) : end
    }

    if ch == "@" || ch == "?" || ch == "$" {
      return command.index(after: afterDollar)
    }

    if ch.isNumber {
      var numberEnd = afterDollar
      while numberEnd < end, command[numberEnd].isNumber {
        numberEnd = command.index(after: numberEnd)
      }
      return numberEnd
    }

    if ch.isLetter || ch == "_" {
      var nameEnd = afterDollar
      while nameEnd < end,
        command[nameEnd].isLetter || command[nameEnd].isNumber
          || command[nameEnd] == "_"
      {
        nameEnd = command.index(after: nameEnd)
      }
      return nameEnd
    }

    return nil
  }

  private static let operatorStartCharacters: Set<Character> = [
    "|", "&", ";", "(", ")", "<", ">", "$",
  ]

  private static func plainWordEnd(
    _ command: String, from start: String.Index, end: String.Index
  ) -> String.Index {
    var index = start
    while index < end {
      let ch = command[index]
      if ch.isWhitespace || ch == "'" || ch == "\"" || operatorStartCharacters.contains(ch) {
        break
      }
      index = command.index(after: index)
    }
    return index
  }

  private static func isAssignment(_ word: String) -> Bool {
    guard let equalsIndex = word.firstIndex(of: "=") else { return false }
    let name = word[word.startIndex..<equalsIndex]
    guard let first = name.first, first.isLetter || first == "_" else { return false }
    return name.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
  }
}
