import Foundation
import Testing

@testable import ApprovalCore

@Suite struct PatchParserTests {
  @Test func diffOrdersContextRemovedAndAddedLines() {
    let old = "a\nb\nc"
    let new = "a\nx\nc"
    let diff = PatchParser.diff(old: old, new: new)
    #expect(diff.map(\.kind) == [.context, .removed, .added, .context])
    #expect(diff.map(\.text) == ["a", "b", "x", "c"])
  }

  @Test func diffHandlesPureInsertion() {
    let old = "a\nb"
    let new = "a\nX\nb"
    let diff = PatchParser.diff(old: old, new: new)
    #expect(diff.map(\.kind) == [.context, .added, .context])
    #expect(diff.map(\.text) == ["a", "X", "b"])
  }

  @Test func diffStripsCarriageReturnsFromCRLFText() {
    let old = "a\r\nb\r\nc"
    let new = "a\r\nx\r\nc"
    let diff = PatchParser.diff(old: old, new: new)
    #expect(diff.map(\.kind) == [.context, .removed, .added, .context])
    #expect(diff.map(\.text) == ["a", "b", "x", "c"])
    #expect(diff.allSatisfy { !$0.text.contains("\r") })
  }

  @Test func diffHandlesPureDeletion() {
    let old = "a\nb\nc"
    let new = "a\nc"
    let diff = PatchParser.diff(old: old, new: new)
    #expect(diff.map(\.kind) == [.context, .removed, .context])
    #expect(diff.map(\.text) == ["a", "b", "c"])
  }

  @Test func collapsesLongUnchangedRunsAroundAChange() {
    let oldLines = (1...20).map { "line\($0)" }
    var newLines = oldLines
    newLines[9] = "CHANGED"
    let diff = PatchParser.diff(
      old: oldLines.joined(separator: "\n"), new: newLines.joined(separator: "\n"))

    #expect(diff.first?.kind == .collapsed)
    #expect(diff.first?.text == "6 unchanged lines")
    #expect(diff.last?.kind == .collapsed)
    #expect(diff.last?.text == "7 unchanged lines")

    let kinds = diff.map(\.kind)
    #expect(kinds.filter { $0 == .removed }.count == 1)
    #expect(kinds.filter { $0 == .added }.count == 1)
    #expect(kinds.filter { $0 == .context }.count == 6)
  }

  @Test func fallbackShowsFewerThanFourUnchangedLinesInFull() {
    let threeHidden = PatchParser.diff(
      old: "a\nb\nc\nd\ne\nf\nold", new: "a\nb\nc\nd\ne\nf\nnew")
    #expect(!threeHidden.contains { $0.kind == .collapsed })
    #expect(threeHidden.first?.text == "a")

    let fourHidden = PatchParser.diff(
      old: "a\nb\nc\nd\ne\nf\ng\nold", new: "a\nb\nc\nd\ne\nf\ng\nnew")
    #expect(fourHidden.first == DiffLine(kind: .collapsed, text: "4 unchanged lines"))
    #expect(fourHidden.dropFirst().first?.text == "e")
  }

  @Test func claudeEditFixtureFallbackStartsAtItsFirstLine() throws {
    let data = try FixtureLoader.data("claude-edit")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let old = try #require(decoded["tool_input"]?["old_string"]?.stringValue)
    let new = try #require(decoded["tool_input"]?["new_string"]?.stringValue)
    let diff = PatchParser.diff(old: old, new: new)
    #expect(!diff.contains { $0.kind == .collapsed })
    #expect(diff.first?.text == "func applyDiscount(to total: Decimal, code: String?) -> Decimal {")
  }

  @Test func diffOfTextsEndingWithNewlinesHasNoPhantomLastLine() {
    let diff = PatchParser.diff(old: "a\nb\n", new: "a\nc\n")
    #expect(diff.map(\.kind) == [.context, .removed, .added])
    #expect(diff.map(\.text) == ["a", "b", "c"])
  }

  @Test func lastLineShowsRemovedAndAddedWhenOnlyOneSideEndsWithNewline() {
    let diff = PatchParser.diff(old: "a\nb", new: "a\nb\n")
    #expect(diff.map(\.kind) == [.context, .removed, .added])
    #expect(diff.map(\.text) == ["a", "b", "b"])
  }

  @Test func gitRangesAreStrippedFromHunkHeaders() {
    let patch = [
      "*** Begin Patch",
      "*** Update File: a.swift",
      "@@ -0,0 +1,2 @@",
      "+x",
      "+y",
      "@@ -10,3 +12,4 @@ func foo()",
      " kept",
      "-old",
      "+new",
      "@@ -20 +22 @@",
      "-gone",
      "*** End Patch",
    ].joined(separator: "\n")
    let lines = PatchParser.files(inApplyPatch: patch).first?.lines ?? []
    #expect(
      lines == [
        DiffLine(kind: .added, text: "x"),
        DiffLine(kind: .added, text: "y"),
        DiffLine(kind: .collapsed, text: "func foo()"),
        DiffLine(kind: .context, text: "kept"),
        DiffLine(kind: .removed, text: "old"),
        DiffLine(kind: .added, text: "new"),
        DiffLine(kind: .collapsed, text: "…"),
        DiffLine(kind: .removed, text: "gone"),
      ])
  }

  @Test func bareHunkHeaderAtTheTopAddsNoRow() {
    let patch = [
      "*** Begin Patch",
      "*** Update File: a.swift",
      "@@",
      "-a",
      "+b",
      "@@",
      "-c",
      "+d",
      "*** End Patch",
    ].joined(separator: "\n")
    let lines = PatchParser.files(inApplyPatch: patch).first?.lines ?? []
    #expect(lines.map(\.kind) == [.removed, .added, .collapsed, .removed, .added])
    #expect(lines[2].text == "…")
  }

  @Test func blankLinesAfterEndPatchBelongToNoFile() {
    let patch = "*** Begin Patch\n*** Delete File: a.swift\n*** End Patch"
    #expect(PatchParser.files(inApplyPatch: patch + "\n").first?.lines == [])
    #expect(PatchParser.files(inApplyPatch: patch + "\n\n").first?.lines == [])
  }

  @Test func previewTreatsAFinalNewlineAsTheEndOfTheLastLine() {
    let (lines, remaining) = PatchParser.preview(of: "a\nb\n", lineLimit: 40)
    #expect(lines == ["a", "b"])
    #expect(remaining == 0)
    #expect(PatchParser.preview(of: "", lineLimit: 40).lines.isEmpty)
  }

  @Test func parsesApplyPatchFixtureIntoThreeFiles() throws {
    let data = try FixtureLoader.data("codex-apply-patch")
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    let command = try #require(decoded["tool_input"]?["command"]?.stringValue)
    let files = PatchParser.files(inApplyPatch: command)
    #expect(files.count == 3)

    #expect(files[0].operation == .add)
    #expect(files[0].path == "Sources/Checkout/DiscountCalculator.swift")
    #expect(files[0].movedTo == nil)
    #expect(files[0].lines.allSatisfy { $0.kind == .added })
    #expect(files[0].lines.count == 7)

    #expect(files[1].operation == .update)
    #expect(files[1].path == "Sources/Checkout/CheckoutService.swift")
    #expect(files[1].movedTo == "Sources/Checkout/CheckoutService.swift")
    #expect(
      files[1].lines.map(\.kind) == [.collapsed, .context, .context, .removed, .added, .added])
    #expect(files[1].lines.first?.text == "func total(for order: Order) -> Decimal {")
    #expect(files[1].lines.contains { $0.text == "*** End of File" } == false)

    #expect(files[2].operation == .delete)
    #expect(files[2].path == "Sources/Checkout/LegacyDiscount.swift")
    #expect(files[2].lines.isEmpty)
  }

  @Test func previewReturnsLimitedLinesAndRemainingCount() {
    let content = (1...50).map { "line\($0)" }.joined(separator: "\n")
    let (lines, remaining) = PatchParser.preview(of: content, lineLimit: 40)
    #expect(lines.count == 40)
    #expect(lines.first == "line1")
    #expect(lines.last == "line40")
    #expect(remaining == 10)
  }

  @Test func previewReturnsZeroRemainingWhenUnderLimit() {
    let content = "a\nb\nc"
    let (lines, remaining) = PatchParser.preview(of: content, lineLimit: 40)
    #expect(lines == ["a", "b", "c"])
    #expect(remaining == 0)
  }
}
