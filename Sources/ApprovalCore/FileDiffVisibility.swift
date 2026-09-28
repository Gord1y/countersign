import Foundation

extension FileDiffBuilder {
  static let enclosingBlockSearchLimit = 60
  static let minimumContextLines = 2
  static let fallbackContextLines = 4
  static let blockCloserTokens = ["}", "]", ")", "end", "fi", "done", "esac"]

  static func numberedDiff(old: String, new: String) -> [NumberedLine] {
    let oldLines = TextLine.split(old)
    let newLines = TextLine.split(new)
    let difference = newLines.difference(from: oldLines)

    var removedOffsets: Set<Int> = []
    var insertedOffsets: Set<Int> = []
    for change in difference {
      switch change {
      case .remove(let offset, _, _):
        removedOffsets.insert(offset)
      case .insert(let offset, _, _):
        insertedOffsets.insert(offset)
      }
    }

    var result: [NumberedLine] = []
    var i = 0
    var j = 0
    while i < oldLines.count || j < newLines.count {
      if i < oldLines.count, removedOffsets.contains(i) {
        result.append(
          NumberedLine(kind: .removed, text: oldLines[i].text, oldNumber: i + 1, newNumber: nil))
        i += 1
      } else if j < newLines.count, insertedOffsets.contains(j) {
        result.append(
          NumberedLine(kind: .added, text: newLines[j].text, oldNumber: nil, newNumber: j + 1))
        j += 1
      } else if i < oldLines.count, j < newLines.count {
        result.append(
          NumberedLine(
            kind: .context, text: oldLines[i].text, oldNumber: i + 1, newNumber: j + 1))
        i += 1
        j += 1
      } else if i < oldLines.count {
        result.append(
          NumberedLine(kind: .removed, text: oldLines[i].text, oldNumber: i + 1, newNumber: nil))
        i += 1
      } else {
        result.append(
          NumberedLine(kind: .added, text: newLines[j].text, oldNumber: nil, newNumber: j + 1))
        j += 1
      }
    }
    return result
  }

  static func segments(for lines: [NumberedLine]) -> [DiffSegment] {
    guard !lines.isEmpty else { return [] }
    let runs = changedRuns(in: lines)
    guard !runs.isEmpty else { return [.visible(lines)] }

    var ranges = runs.map { visibleRange(for: $0, in: lines) }
    ranges.sort { $0.start < $1.start }

    var merged: [(start: Int, end: Int)] = []
    for range in ranges {
      if let last = merged.last, range.start <= last.end + 1 {
        merged[merged.count - 1].end = max(last.end, range.end)
      } else {
        merged.append(range)
      }
    }

    var result: [DiffSegment] = []
    var cursor = 0
    for range in merged {
      if range.start > cursor {
        result.append(.gap(Array(lines[cursor..<range.start])))
      }
      result.append(.visible(Array(lines[range.start...range.end])))
      cursor = range.end + 1
    }
    if cursor < lines.count {
      result.append(.gap(Array(lines[cursor...])))
    }
    return result
  }

  static func changedRuns(in lines: [NumberedLine]) -> [(start: Int, end: Int)] {
    var runs: [(start: Int, end: Int)] = []
    var index = 0
    while index < lines.count {
      if lines[index].kind == .context {
        index += 1
        continue
      }
      var end = index
      while end < lines.count, lines[end].kind != .context {
        end += 1
      }
      runs.append((start: index, end: end - 1))
      index = end
    }
    return runs
  }

  static func visibleRange(for run: (start: Int, end: Int), in lines: [NumberedLine]) -> (
    start: Int, end: Int
  ) {
    let runLines = lines[run.start...run.end]
    let minIndent =
      runLines.compactMap { line in isBlank(line.text) ? nil : indentWidth(line.text) }
      .min() ?? 0

    var visibleStart = run.start
    var visibleEnd = run.end
    var usedHeuristic = false

    if minIndent > 0,
      let headerIndex = findHeader(before: run.start, minIndent: minIndent, in: lines),
      run.start - headerIndex <= enclosingBlockSearchLimit
    {
      let headerIndent = indentWidth(lines[headerIndex].text)
      var resolvedHeaderIndex = headerIndex
      if startsWithClosingBracket(lines[headerIndex].text),
        let signatureStart = findSignatureStart(
          before: headerIndex, indent: headerIndent, in: lines),
        run.start - signatureStart <= enclosingBlockSearchLimit
      {
        resolvedHeaderIndex = signatureStart
      }
      if let footer = findFooterBoundary(after: run.end, maxIndent: headerIndent, in: lines),
        footer.index - run.end <= enclosingBlockSearchLimit
      {
        visibleStart = resolvedHeaderIndex
        visibleEnd = footer.included ? footer.index : footer.index - 1
        usedHeuristic = true
      }
    }

    if !usedHeuristic {
      visibleStart = run.start - fallbackContextLines
      visibleEnd = run.end + fallbackContextLines
    }

    visibleStart = min(visibleStart, run.start - minimumContextLines)
    visibleEnd = max(visibleEnd, run.end + minimumContextLines)
    visibleStart = max(0, visibleStart)
    visibleEnd = min(lines.count - 1, visibleEnd)
    return (start: visibleStart, end: visibleEnd)
  }

  static func findHeader(before start: Int, minIndent: Int, in lines: [NumberedLine]) -> Int? {
    var index = start - 1
    while index >= 0 {
      let text = lines[index].text
      if !isBlank(text), indentWidth(text) < minIndent {
        return index
      }
      index -= 1
    }
    return nil
  }

  static func findSignatureStart(before index: Int, indent: Int, in lines: [NumberedLine]) -> Int? {
    var cursor = index - 1
    while cursor >= 0 {
      let text = lines[cursor].text
      if !isBlank(text), indentWidth(text) == indent, !startsWithClosingBracket(text) {
        return cursor
      }
      cursor -= 1
    }
    return nil
  }

  static func startsWithClosingBracket(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix(")") || trimmed.hasPrefix("]") || trimmed.hasPrefix("}")
  }

  static func findFooterBoundary(after end: Int, maxIndent: Int, in lines: [NumberedLine]) -> (
    index: Int, included: Bool
  )? {
    var index = end + 1
    while index < lines.count {
      let text = lines[index].text
      if !isBlank(text), indentWidth(text) <= maxIndent {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let included = blockCloserTokens.contains { trimmed.hasPrefix($0) }
        return (index: index, included: included)
      }
      index += 1
    }
    return nil
  }

  static func isBlank(_ text: String) -> Bool {
    text.allSatisfy { $0 == " " || $0 == "\t" }
  }

  static func indentWidth(_ text: String) -> Int {
    var width = 0
    for character in text {
      if character == " " {
        width += 1
      } else if character == "\t" {
        width += 4
      } else {
        break
      }
    }
    return width
  }
}
