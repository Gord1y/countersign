import Foundation

struct HookCommandWord: Sendable, Equatable {
  let range: Range<Int>
  let value: String
}

enum HookCommand {
  static let executableName = "countersign"
  static let subcommand = "hook"
  static let hostOption = "--host"

  static func words(in scalars: [Unicode.Scalar], limit: Int) -> [HookCommandWord] {
    var words: [HookCommandWord] = []
    var index = 0
    while words.count < limit {
      while index < scalars.count, isWhitespace(scalars[index]) {
        index += 1
      }
      guard index < scalars.count else { break }
      let start = index
      let opening = scalars[index]
      if opening == "\"" || opening == "'" {
        guard let closing = scalars[(index + 1)...].firstIndex(of: opening) else { break }
        words.append(
          HookCommandWord(range: start..<(closing + 1), value: text(scalars[(start + 1)..<closing]))
        )
        index = closing + 1
      } else {
        while index < scalars.count, !isWhitespace(scalars[index]) {
          index += 1
        }
        words.append(HookCommandWord(range: start..<index, value: text(scalars[start..<index])))
      }
    }
    return words
  }

  static func isCountersignHook(_ command: String) -> Bool {
    let words = words(in: Array(command.unicodeScalars), limit: 2)
    guard words.count == 2 else { return false }
    return isCountersignExecutable(words[0].value) && words[1].value == subcommand
  }

  static func arguments(for host: Host) -> [String] {
    [subcommand, hostOption, host.rawValue]
  }

  static func isCommand(_ command: String, running executablePath: String, for host: Host)
    -> Bool
  {
    words(in: Array(command.unicodeScalars), limit: Int.max).map(\.value)
      == [executablePath] + arguments(for: host)
  }

  static func isCountersignExecutable(_ path: String) -> Bool {
    path.split(separator: "/").last.map(String.init) == executableName
  }

  static func shellWord(_ path: String) -> String {
    let safe = path.unicodeScalars.allSatisfy { scalar in
      scalar.isASCII
        && (CharacterSet.alphanumerics.contains(scalar)
          || "/._-+@%:,=".unicodeScalars.contains(scalar))
    }
    if safe, !path.isEmpty {
      return path
    }
    return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func command(host: Host, executablePath: String) -> String {
    ([shellWord(executablePath)] + arguments(for: host)).joined(separator: " ")
  }

  private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
  }

  private static func text(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
  }
}
