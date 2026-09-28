public struct DropdownNavigation: Sendable, Equatable {
  public static let digitLimit = 9

  public let rowCount: Int
  public private(set) var highlightedRow: Int

  public init(rowCount: Int, highlighting startRow: Int = 0) {
    self.rowCount = max(rowCount, 0)
    self.highlightedRow = (0..<max(rowCount, 0)).contains(startRow) ? startRow : 0
  }

  public mutating func moveDown() {
    guard rowCount > 0 else { return }
    highlightedRow = (highlightedRow + 1) % rowCount
  }

  public mutating func moveUp() {
    guard rowCount > 0 else { return }
    highlightedRow = (highlightedRow + rowCount - 1) % rowCount
  }

  public mutating func highlight(_ row: Int) {
    guard (0..<rowCount).contains(row) else { return }
    highlightedRow = row
  }

  public func row(forDigit digit: Int) -> Int? {
    guard (1...Self.digitLimit).contains(digit), digit <= rowCount else { return nil }
    return digit - 1
  }
}
