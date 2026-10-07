public struct DiffSummary: Equatable, Sendable {
  public let added: Int
  public let removed: Int

  public init(unifiedDiff: String) {
    var added = 0
    var removed = 0
    var remainingOld = 0
    var remainingNew = 0
    for line in unifiedDiff.split(separator: "\n", omittingEmptySubsequences: false) {
      if remainingOld > 0 || remainingNew > 0 {
        if line.hasPrefix("-") {
          removed += 1
          remainingOld -= 1
        } else if line.hasPrefix("+") {
          added += 1
          remainingNew -= 1
        } else {
          remainingOld -= 1
          remainingNew -= 1
        }
        continue
      }
      let counts = Self.hunkCounts(in: line)
      remainingOld = counts?.old ?? 0
      remainingNew = counts?.new ?? 0
    }
    self.added = added
    self.removed = removed
  }

  public var text: String {
    switch (added, removed) {
    case (0, 0): return "no lines changed"
    case (_, 0): return "\(Self.lines(added)) added"
    case (0, _): return "\(Self.lines(removed)) removed"
    default: return "\(Self.lines(added)) added, \(removed) removed"
    }
  }

  private static func lines(_ count: Int) -> String {
    count == 1 ? "1 line" : "\(count) lines"
  }

  private static func hunkCounts(in line: Substring) -> (old: Int, new: Int)? {
    guard line.hasPrefix("@@ -") else { return nil }
    let fields = line.dropFirst(3).split(separator: " ", omittingEmptySubsequences: true)
    guard fields.count >= 2, fields[1].hasPrefix("+"),
      let old = rangeCount(fields[0].dropFirst()),
      let new = rangeCount(fields[1].dropFirst())
    else { return nil }
    return (old, new)
  }

  private static func rangeCount(_ range: Substring) -> Int? {
    let parts = range.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count <= 2, let start = parts.first, Int(start) != nil else { return nil }
    guard parts.count == 2 else { return 1 }
    guard let count = Int(parts[1]), count >= 0 else { return nil }
    return count
  }
}
