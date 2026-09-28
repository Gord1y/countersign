import Foundation
import Testing

@testable import ApprovalCore

private func numbered(_ count: Int) -> [String] {
  (1...count).map(String.init)
}

@Suite struct UnifiedDiffTests {
  @Test func printsNothingWithoutChanges() {
    #expect(UnifiedDiff.render(old: "a\nb\n", new: "a\nb\n", oldLabel: "f", newLabel: "f") == "")
    #expect(UnifiedDiff.render(old: "", new: "", oldLabel: "f", newLabel: "f") == "")
  }

  @Test func showsThreeLinesOfContextAroundAChange() {
    let old = "a\nb\nc\nd\ne\nf\ng\nh\n"
    let new = "a\nb\nc\nd\nE\nf\ng\nh\n"
    let expected = """
      --- /tmp/settings.json
      +++ /tmp/settings.json
      @@ -2,7 +2,7 @@
       b
       c
       d
      -e
      +E
       f
       g
       h

      """
    #expect(
      UnifiedDiff.render(
        old: old, new: new, oldLabel: "/tmp/settings.json", newLabel: "/tmp/settings.json")
        == expected)
  }

  @Test func showsANewFileAgainstDevNull() {
    let expected = "--- /dev/null\n+++ f\n@@ -0,0 +1,2 @@\n+x\n+y\n"
    #expect(
      UnifiedDiff.render(old: "", new: "x\ny\n", oldLabel: "/dev/null", newLabel: "f") == expected)
  }

  @Test func showsARemovalAtTheEnd() {
    let expected = "--- f\n+++ f\n@@ -1,2 +1 @@\n a\n-b\n"
    #expect(UnifiedDiff.render(old: "a\nb\n", new: "a\n", oldLabel: "f", newLabel: "f") == expected)
  }

  @Test func omitsTheCountOfASingleLine() {
    let expected = "--- f\n+++ f\n@@ -1 +1 @@\n-a\n+b\n"
    #expect(UnifiedDiff.render(old: "a\n", new: "b\n", oldLabel: "f", newLabel: "f") == expected)
  }

  @Test func splitsDistantChangesIntoHunks() {
    var changed = numbered(20)
    changed[1] = "two"
    changed[17] = "eighteen"
    let old = numbered(20).joined(separator: "\n") + "\n"
    let new = changed.joined(separator: "\n") + "\n"
    let expected = """
      --- f
      +++ f
      @@ -1,5 +1,5 @@
       1
      -2
      +two
       3
       4
       5
      @@ -15,6 +15,6 @@
       15
       16
       17
      -18
      +eighteen
       19
       20

      """
    #expect(UnifiedDiff.render(old: old, new: new, oldLabel: "f", newLabel: "f") == expected)
  }

  @Test func mergesChangesWhoseContextTouches() {
    var changed = numbered(12)
    changed[1] = "two"
    changed[8] = "nine"
    let old = numbered(12).joined(separator: "\n") + "\n"
    let new = changed.joined(separator: "\n") + "\n"
    let output = UnifiedDiff.render(old: old, new: new, oldLabel: "f", newLabel: "f")
    #expect(output.components(separatedBy: "@@ ").count == 2)
    #expect(output.contains("@@ -1,12 +1,12 @@\n"))
  }

  @Test func honoursACustomContext() {
    let output = UnifiedDiff.render(
      old: "a\nb\nc\n", new: "a\nB\nc\n", oldLabel: "f", newLabel: "f", context: 0)
    #expect(output == "--- f\n+++ f\n@@ -2 +2 @@\n-b\n+B\n")
  }

  @Test func stripsCarriageReturnsFromPrintedLines() {
    let output = UnifiedDiff.render(
      old: "a\r\nb\r\n", new: "a\r\nc\r\n", oldLabel: "f", newLabel: "f")
    #expect(output == "--- f\n+++ f\n@@ -1,2 +1,2 @@\n a\n-b\n+c\n")
  }

  @Test func computesHunkRangesAndHeaders() {
    let lines = FileDiffBuilder.numberedDiff(old: "a\nb\n", new: "a\nx\nb\n")
    let ranges = UnifiedDiff.hunkRanges(in: lines, context: 3)
    #expect(ranges == [0...2])
    #expect(UnifiedDiff.header(for: 0...2, in: lines) == "@@ -1,2 +1,3 @@")
    #expect(UnifiedDiff.hunkRanges(in: [], context: 3) == [])
  }
}
