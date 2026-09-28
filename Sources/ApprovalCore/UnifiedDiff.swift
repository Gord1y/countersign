import Foundation

public enum UnifiedDiff {
  public static let defaultContext = 3

  public static func render(
    old: String, new: String, oldLabel: String, newLabel: String,
    context: Int = defaultContext
  ) -> String {
    let lines = FileDiffBuilder.numberedDiff(old: old, new: new)
    let hunks = hunkRanges(in: lines, context: context)
    guard !hunks.isEmpty else { return "" }
    var output = "--- \(oldLabel)\n+++ \(newLabel)\n"
    for hunk in hunks {
      output += header(for: hunk, in: lines) + "\n"
      for line in lines[hunk] {
        output += prefix(for: line.kind) + line.text + "\n"
      }
    }
    return output
  }

  static func hunkRanges(in lines: [NumberedLine], context: Int) -> [ClosedRange<Int>] {
    var ranges: [ClosedRange<Int>] = []
    for (index, line) in lines.enumerated() where line.kind != .context {
      let start = max(0, index - context)
      let end = min(lines.count - 1, index + context)
      if let last = ranges.last, start <= last.upperBound + 1 {
        ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, end)
      } else {
        ranges.append(start...end)
      }
    }
    return ranges
  }

  static func header(for hunk: ClosedRange<Int>, in lines: [NumberedLine]) -> String {
    let before = lines[..<hunk.lowerBound]
    let inside = lines[hunk]
    let oldBefore = before.filter { $0.kind != .added }.count
    let newBefore = before.filter { $0.kind != .removed }.count
    let oldCount = inside.filter { $0.kind != .added }.count
    let newCount = inside.filter { $0.kind != .removed }.count
    return
      "@@ -\(span(start: oldBefore, count: oldCount)) +\(span(start: newBefore, count: newCount)) @@"
  }

  private static func span(start linesBefore: Int, count: Int) -> String {
    let start = count == 0 ? linesBefore : linesBefore + 1
    return count == 1 ? "\(start)" : "\(start),\(count)"
  }

  private static func prefix(for kind: NumberedLineKind) -> String {
    switch kind {
    case .context: return " "
    case .added: return "+"
    case .removed: return "-"
    }
  }
}
