import Foundation

extension FileDiffBuilder {
  static func hunks(from lines: [DiffLine]) -> [[DiffLine]] {
    var result: [[DiffLine]] = []
    var current: [DiffLine] = []
    for line in lines {
      if line.kind == .collapsed {
        if !current.isEmpty {
          result.append(current)
          current = []
        }
        continue
      }
      current.append(line)
    }
    if !current.isEmpty {
      result.append(current)
    }
    return result
  }

  static func applyingHunks(_ diffLines: [DiffLine], to content: String) -> String? {
    let hunkGroups = hunks(from: diffLines)
    guard !hunkGroups.isEmpty else { return content }

    let realTextLines = TextLine.split(content)
    let realLines = realTextLines.map(\.text)
    var resultLines: [String] = []
    var cursor = 0
    var searchFrom = 0

    for hunk in hunkGroups {
      let pattern = hunk.filter { $0.kind == .context || $0.kind == .removed }.map(\.text)
      guard let matchStart = firstIndex(of: pattern, in: realLines, from: searchFrom) else {
        return nil
      }
      resultLines.append(contentsOf: realLines[cursor..<matchStart])

      var pointer = matchStart
      for line in hunk {
        switch line.kind {
        case .context:
          resultLines.append(realLines[pointer])
          pointer += 1
        case .removed:
          pointer += 1
        case .added:
          resultLines.append(line.text)
        case .collapsed:
          continue
        }
      }
      cursor = pointer
      searchFrom = pointer
    }

    resultLines.append(contentsOf: realLines[cursor...])
    let joined = resultLines.joined(separator: "\n")
    let keepsFinalNewline = realTextLines.last?.endsWithNewline ?? false
    return keepsFinalNewline && !resultLines.isEmpty ? joined + "\n" : joined
  }

  static func firstIndex(of pattern: [String], in lines: [String], from start: Int) -> Int? {
    guard !pattern.isEmpty else { return start }
    guard start <= lines.count - pattern.count else { return nil }
    var index = start
    while index <= lines.count - pattern.count {
      if Array(lines[index..<index + pattern.count]) == pattern {
        return index
      }
      index += 1
    }
    return nil
  }
}
