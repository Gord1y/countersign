import Testing

@testable import ApprovalCore

@Suite struct DropdownNavigationTests {
  @Test func opensOnTheFirstRowByDefault() {
    #expect(DropdownNavigation(rowCount: 3).highlightedRow == 0)
  }

  @Test func opensOnTheRowItIsGiven() {
    #expect(DropdownNavigation(rowCount: 3, highlighting: 2).highlightedRow == 2)
  }

  @Test func aStartRowOutsideTheRowsOpensOnTheFirstRow() {
    #expect(DropdownNavigation(rowCount: 3, highlighting: 3).highlightedRow == 0)
    #expect(DropdownNavigation(rowCount: 3, highlighting: -1).highlightedRow == 0)
  }

  @Test func reopeningResetsTheHighlight() {
    var navigation = DropdownNavigation(rowCount: 3)
    navigation.moveDown()
    navigation.moveDown()
    #expect(navigation.highlightedRow == 2)
    navigation = DropdownNavigation(rowCount: 3)
    #expect(navigation.highlightedRow == 0)
  }

  @Test func movingDownWrapsFromTheLastRowToTheFirst() {
    var navigation = DropdownNavigation(rowCount: 3)
    navigation.moveDown()
    #expect(navigation.highlightedRow == 1)
    navigation.moveDown()
    navigation.moveDown()
    #expect(navigation.highlightedRow == 0)
  }

  @Test func movingUpWrapsFromTheFirstRowToTheLast() {
    var navigation = DropdownNavigation(rowCount: 3)
    navigation.moveUp()
    #expect(navigation.highlightedRow == 2)
    navigation.moveUp()
    #expect(navigation.highlightedRow == 1)
  }

  @Test func aSingleRowStaysHighlightedWhenMoving() {
    var navigation = DropdownNavigation(rowCount: 1)
    navigation.moveDown()
    #expect(navigation.highlightedRow == 0)
    navigation.moveUp()
    #expect(navigation.highlightedRow == 0)
  }

  @Test func noRowsMeansNothingMovesAndNoDigitPicks() {
    var navigation = DropdownNavigation(rowCount: 0)
    navigation.moveDown()
    navigation.moveUp()
    #expect(navigation.highlightedRow == 0)
    #expect(navigation.row(forDigit: 1) == nil)
    #expect(DropdownNavigation(rowCount: -2).rowCount == 0)
  }

  @Test func hoveringHighlightsARowInsideTheRows() {
    var navigation = DropdownNavigation(rowCount: 3)
    navigation.highlight(2)
    #expect(navigation.highlightedRow == 2)
    navigation.highlight(3)
    navigation.highlight(-1)
    #expect(navigation.highlightedRow == 2)
  }

  @Test func aDigitPicksItsRowWithinTheRows() {
    let navigation = DropdownNavigation(rowCount: 3)
    #expect(navigation.row(forDigit: 1) == 0)
    #expect(navigation.row(forDigit: 3) == 2)
    #expect(navigation.row(forDigit: 4) == nil)
    #expect(navigation.row(forDigit: 0) == nil)
  }

  @Test func onlyTheFirstNineRowsHaveADigit() {
    let navigation = DropdownNavigation(rowCount: 12)
    #expect(navigation.row(forDigit: 9) == 8)
    #expect(navigation.row(forDigit: 10) == nil)
  }
}
