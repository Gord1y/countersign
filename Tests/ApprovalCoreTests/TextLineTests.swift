import Testing

@testable import ApprovalCore

@Suite struct TextLineTests {
  @Test func emptyTextHasNoLines() {
    #expect(TextLine.split("").isEmpty)
  }

  @Test func textWithoutFinalNewlineEndsWithAnUnterminatedLine() {
    #expect(
      TextLine.split("a\nb") == [
        TextLine(text: "a", endsWithNewline: true),
        TextLine(text: "b", endsWithNewline: false),
      ])
  }

  @Test func finalNewlineEndsTheLastLineInsteadOfStartingAnother() {
    #expect(
      TextLine.split("a\nb\n") == [
        TextLine(text: "a", endsWithNewline: true),
        TextLine(text: "b", endsWithNewline: true),
      ])
  }

  @Test func blankLinesBeforeTheFinalNewlineAreKept() {
    #expect(TextLine.split("\n") == [TextLine(text: "", endsWithNewline: true)])
    #expect(TextLine.split("a\n\n").map(\.text) == ["a", ""])
  }

  @Test func carriageReturnsBeforeNewlinesAreStripped() {
    #expect(
      TextLine.split("a\r\nb\r\n") == [
        TextLine(text: "a", endsWithNewline: true),
        TextLine(text: "b", endsWithNewline: true),
      ])
  }
}
