public struct DiffSummary: Equatable, Sendable {
  public let added: Int
  public let removed: Int

  public init(unifiedDiff: String) {
    var added = 0
    var removed = 0
    for line in unifiedDiff.split(separator: "\n", omittingEmptySubsequences: true) {
      if line.hasPrefix("+++") || line.hasPrefix("---") { continue }
      if line.hasPrefix("+") {
        added += 1
      } else if line.hasPrefix("-") {
        removed += 1
      }
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
}
