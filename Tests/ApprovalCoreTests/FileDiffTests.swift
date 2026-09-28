import Foundation
import Testing

@testable import ApprovalCore

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func makeEditRequest(cwd: String, path: String, oldString: String, newString: String)
  -> ApprovalRequest
{
  ApprovalRequest(
    host: .claude,
    sessionID: "session-1",
    cwd: cwd,
    permissionMode: nil,
    transcriptPath: nil,
    agentID: nil,
    agentType: nil,
    toolName: "Edit",
    toolInput: .object([:]),
    kind: .permission(
      PermissionPrompt(
        body: .edit(path: path, oldString: oldString, newString: newString, replaceAll: false),
        suggestions: [])))
}

private func makeWriteRequest(cwd: String, path: String, content: String) -> ApprovalRequest {
  ApprovalRequest(
    host: .claude,
    sessionID: "session-1",
    cwd: cwd,
    permissionMode: nil,
    transcriptPath: nil,
    agentID: nil,
    agentType: nil,
    toolName: "Write",
    toolInput: .object([:]),
    kind: .permission(PermissionPrompt(body: .write(path: path, content: content), suggestions: []))
  )
}

private func makePatchRequest(cwd: String, patchText: String) -> ApprovalRequest {
  ApprovalRequest(
    host: .codex,
    sessionID: "session-1",
    cwd: cwd,
    permissionMode: nil,
    transcriptPath: nil,
    agentID: nil,
    agentType: nil,
    toolName: "apply_patch",
    toolInput: .object([:]),
    kind: .permission(PermissionPrompt(body: .patch(text: patchText), suggestions: [])))
}

@Suite struct FileDiffTests {
  @Test func editShowsFunctionFromHeaderToClosingBrace() throws {
    let content = [
      "import Foundation",
      "",
      "struct Padding {",
      "  let p1 = 1",
      "  let p2 = 2",
      "  let p3 = 3",
      "  let p4 = 4",
      "  let p5 = 5",
      "  let p6 = 6",
      "  let p7 = 7",
      "  let p8 = 8",
      "}",
      "",
      "func applyDiscount(to total: Decimal, code: String?) -> Decimal {",
      "  guard let code, !code.isEmpty else {",
      "    return total",
      "  }",
      "  let filler1 = 1",
      "  let filler2 = 2",
      "  let filler3 = 3",
      "  let filler4 = 4",
      "  let filler5 = 5",
      "  let rate = discountRate(for: code)",
      "  let bounded = rate",
      "  return total * (1 - bounded)",
      "}",
      "",
      "struct Trailing {",
      "  let t1 = 1",
      "  let t2 = 2",
      "  let t3 = 3",
      "  let t4 = 4",
      "  let t5 = 5",
      "  let t6 = 6",
      "  let t7 = 7",
      "  let t8 = 8",
      "}",
    ].joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/x.swift", fileContent: content,
        oldString: "  let rate = discountRate(for: code)",
        newString: "  let rate = min(discountRate(for: code), maximumDiscountRate)",
        replaceAll: false))

    #expect(diff.status == .modified)
    #expect(diff.segments.count == 3)

    guard case .gap(let before) = diff.segments[0] else {
      Issue.record("expected a leading gap")
      return
    }
    #expect(before.first?.oldNumber == 1)
    #expect(before.last?.oldNumber == 13)

    guard case .visible(let visible) = diff.segments[1] else {
      Issue.record("expected a visible block")
      return
    }
    #expect(
      visible.first?.text == "func applyDiscount(to total: Decimal, code: String?) -> Decimal {")
    #expect(visible.first?.oldNumber == 14)
    #expect(visible.last?.text == "}")
    #expect(visible.last?.oldNumber == 26)
    #expect(visible.contains { $0.kind == .removed && $0.text.contains("discountRate(for: code)") })
    #expect(
      visible.contains {
        $0.kind == .added && $0.text.contains("maximumDiscountRate")
      })

    guard case .gap(let after) = diff.segments[2] else {
      Issue.record("expected a trailing gap")
      return
    }
    #expect(after.first?.oldNumber == 27)
    #expect(after.last?.oldNumber == 37)
  }

  @Test func topLevelEditFallsBackToFourLinesOfContext() throws {
    let content =
      (["import Foundation", ""] + (1...5).map { "let before\($0) = \($0)" }
      + ["let target = 10"] + (1...7).map { "let after\($0) = \($0)" })
      .joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/top.swift", fileContent: content, oldString: "let target = 10",
        newString: "let target = 20", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .gap(let before) = diff.segments[0], case .visible(let visible) = diff.segments[1],
      case .gap(let after) = diff.segments[2]
    else {
      Issue.record("expected gap, visible, gap")
      return
    }
    #expect(before.map(\.oldNumber) == [1, 2, 3])
    #expect(visible.first?.oldNumber == 4)
    #expect(visible.last?.oldNumber == 12)
    #expect(after.first?.oldNumber == 13)
    #expect(after.last?.oldNumber == 15)
  }

  @Test func blockHeaderTooFarAboveFallsBackToFourLinesOfContext() throws {
    var lines = ["func bigFunction() {"]
    lines += (1...85).map { "  let filler\($0) = \($0)" }
    lines.append("  let target = 1")
    lines.append("}")
    lines.append("")
    lines.append("struct After {")
    lines += (1...5).map { "  let a\($0) = \($0)" }
    lines.append("}")
    let content = lines.joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/far.swift", fileContent: content, oldString: "  let target = 1",
        newString: "  let target = 2", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .gap(let before) = diff.segments[0], case .visible(let visible) = diff.segments[1],
      case .gap(let after) = diff.segments[2]
    else {
      Issue.record("expected gap, visible, gap")
      return
    }
    #expect(before.first?.oldNumber == 1)
    #expect(before.last?.oldNumber == 82)
    #expect(visible.first?.oldNumber == 83)
    #expect(visible.last?.oldNumber == 91)
    #expect(after.first?.oldNumber == 92)
    #expect(after.last?.oldNumber == 96)
    #expect(!visible.contains { $0.text == "func bigFunction() {" })
  }

  @Test func replaceAllProducesMultipleVisibleRanges() throws {
    let content =
      ([
        "struct A {", "  func one() -> Int {", "    let cached = compute()", "    return cached",
        "  }", "}", "",
      ]
      + (1...10).map { "let padding\($0) = \($0)" }
      + [
        "", "struct B {", "  func two() -> Int {", "    let cached = compute()",
        "    return cached", "  }", "}",
      ])
      .joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/replace.swift", fileContent: content, oldString: "let cached = compute()",
        newString: "let cached = computeValue()", replaceAll: true))

    let visibleSegments = diff.segments.compactMap { segment -> [NumberedLine]? in
      if case .visible(let lines) = segment { return lines }
      return nil
    }
    #expect(visibleSegments.count == 2)
    #expect(visibleSegments[0].contains { $0.text.contains("computeValue") })
    #expect(visibleSegments[1].contains { $0.text.contains("computeValue") })
    #expect(
      diff.segments.contains { segment in
        if case .gap = segment { return true }
        return false
      })
  }

  @Test func editReturnsNilWhenOldStringNotFound() {
    let diff = FileDiffBuilder.edit(
      path: "/tmp/missing.swift", fileContent: "a\nb\nc", oldString: "not there", newString: "x",
      replaceAll: false)
    #expect(diff == nil)
  }

  @Test func writeWithExistingContentProducesModifiedDiff() throws {
    let content = ["a", "b", "c", "d", "e"].joined(separator: "\n")
    let newContent = ["a", "b", "Z", "d", "e"].joined(separator: "\n")
    let diff = FileDiffBuilder.write(
      path: "/tmp/w.swift", fileContent: content, newContent: newContent)
    #expect(diff.status == .modified)
    let allLines = diff.segments.flatMap { segment -> [NumberedLine] in
      switch segment {
      case .visible(let lines), .gap(let lines): return lines
      }
    }
    #expect(allLines.contains { $0.kind == .removed && $0.text == "c" })
    #expect(allLines.contains { $0.kind == .added && $0.text == "Z" })
  }

  @Test func writeWithNilContentProducesCreatedDiffWithFortyLineGap() {
    let newContent = (1...45).map { "line\($0)" }.joined(separator: "\n")
    let diff = FileDiffBuilder.write(
      path: "/tmp/new.swift", fileContent: nil, newContent: newContent)
    #expect(diff.status == .created)
    #expect(diff.segments.count == 2)
    guard case .visible(let visible) = diff.segments[0], case .gap(let gap) = diff.segments[1]
    else {
      Issue.record("expected visible then gap")
      return
    }
    #expect(visible.count == 40)
    #expect(visible.allSatisfy { $0.kind == .added })
    #expect(visible.first?.newNumber == 1)
    #expect(visible.last?.newNumber == 40)
    #expect(gap.count == 5)
    #expect(gap.first?.newNumber == 41)
    #expect(gap.last?.newNumber == 45)
  }

  @Test func codexUpdateWithMoveLocatesHunksInDocumentOrder() throws {
    let content = [
      "func decoyOne() -> Int {",
      "  let value = 100",
      "  return value",
      "}",
      "",
      "func first() -> Int {",
      "  let value = 1",
      "  return value",
      "}",
      "",
      "func second() -> Int {",
      "  let value = 1",
      "  return value",
      "}",
    ].joined(separator: "\n")

    let hunkLines: [DiffLine] = [
      DiffLine(kind: .collapsed, text: "hunk1"),
      DiffLine(kind: .context, text: "  let value = 1"),
      DiffLine(kind: .removed, text: "  return value"),
      DiffLine(kind: .added, text: "  return value * 2"),
      DiffLine(kind: .collapsed, text: "hunk2"),
      DiffLine(kind: .context, text: "  let value = 1"),
      DiffLine(kind: .removed, text: "  return value"),
      DiffLine(kind: .added, text: "  return value * 2"),
    ]
    let file = PatchFile(
      operation: .update, path: "Sources/OldMath.swift", movedTo: "Sources/Math.swift",
      lines: hunkLines)

    let diff = try #require(FileDiffBuilder.patch(file, fileContent: content))
    #expect(diff.status == .moved(to: "Sources/Math.swift"))

    let newContent = try #require(FileDiffBuilder.applyingHunks(hunkLines, to: content))
    let expected = [
      "func decoyOne() -> Int {",
      "  let value = 100",
      "  return value",
      "}",
      "",
      "func first() -> Int {",
      "  let value = 1",
      "  return value * 2",
      "}",
      "",
      "func second() -> Int {",
      "  let value = 1",
      "  return value * 2",
      "}",
    ].joined(separator: "\n")
    #expect(newContent == expected)
  }

  @Test func codexUpdateReturnsNilForUnlocatableHunk() {
    let hunkLines: [DiffLine] = [
      DiffLine(kind: .collapsed, text: "hunk"),
      DiffLine(kind: .context, text: "  this text does not exist"),
      DiffLine(kind: .removed, text: "  return value"),
      DiffLine(kind: .added, text: "  return value * 2"),
    ]
    let file = PatchFile(
      operation: .update, path: "Sources/Missing.swift", movedTo: nil, lines: hunkLines)
    let diff = FileDiffBuilder.patch(file, fileContent: "func f() {\n  return value\n}")
    #expect(diff == nil)
  }

  @Test func codexDeleteProducesDeletedDiff() throws {
    let file = PatchFile(operation: .delete, path: "Sources/Old.swift", movedTo: nil, lines: [])
    let content = ["line1", "line2", "line3"].joined(separator: "\n")
    let diff = try #require(FileDiffBuilder.patch(file, fileContent: content))
    #expect(diff.status == .deleted)
    guard case .visible(let visible) = diff.segments.first else {
      Issue.record("expected a visible segment")
      return
    }
    #expect(visible.count == 3)
    #expect(visible.allSatisfy { $0.kind == .removed })
    #expect(visible.map(\.oldNumber) == [1, 2, 3])
  }

  @Test func codexDeleteReturnsNilWhenContentIsNil() {
    let file = PatchFile(operation: .delete, path: "Sources/Old.swift", movedTo: nil, lines: [])
    #expect(FileDiffBuilder.patch(file, fileContent: nil) == nil)
  }

  @Test func crlfFilesStripCarriageReturnsAndKeepLineNumbers() {
    let old = "a\r\nb\r\nc"
    let new = "a\r\nX\r\nc"
    let numbered = FileDiffBuilder.numberedDiff(old: old, new: new)
    #expect(numbered.allSatisfy { !$0.text.contains("\r") })
    #expect(
      numbered == [
        NumberedLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
        NumberedLine(kind: .removed, text: "b", oldNumber: 2, newNumber: nil),
        NumberedLine(kind: .added, text: "X", oldNumber: nil, newNumber: 2),
        NumberedLine(kind: .context, text: "c", oldNumber: 3, newNumber: 3),
      ])
  }

  @Test func tabsCountAsFourSpacesForIndentation() throws {
    let content = [
      "struct Outer {",
      "  func withTabs() {",
      "\t\tlet a = 1",
      "\t\tlet b = 2",
      "\t\tlet target = 3",
      "\t\tlet c = 4",
      "\t\tlet d = 5",
      "  }",
      "}",
    ].joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/tabs.swift", fileContent: content, oldString: "\t\tlet target = 3",
        newString: "\t\tlet target = 30", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .visible(let visible) = diff.segments[1] else {
      Issue.record("expected a visible block")
      return
    }
    #expect(visible.first?.text == "  func withTabs() {")
    #expect(visible.last?.text == "  }")
  }

  @Test func multiLineSignatureHeaderIncludesTheWholeSignature() throws {
    let content = [
      "final class Display {",
      "  public func waitForDisplay(",
      "    _ ticket: Ticket,",
      "    pollInterval: Duration,",
      "    shouldAbandon: () -> Bool",
      "  ) -> DisplayLease? {",
      "    let value = 1",
      "    return nil",
      "  }",
      "}",
    ].joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/display.swift", fileContent: content, oldString: "    let value = 1",
        newString: "    let value = 2", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .visible(let visible) = diff.segments[1] else {
      Issue.record("expected a visible block")
      return
    }
    #expect(visible.first?.text == "  public func waitForDisplay(")
    #expect(visible.last?.text == "  }")
  }

  @Test func kotlinStyleClosingParameterListIncludesTheWholeSignature() throws {
    let content = [
      "class Widget {",
      "  fun waitForDisplay(",
      "    ticket: Ticket,",
      "    pollInterval: Long",
      "  ) {",
      "    val value = 1",
      "    return",
      "  }",
      "}",
    ].joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/widget.kt", fileContent: content, oldString: "    val value = 1",
        newString: "    val value = 2", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .visible(let visible) = diff.segments[1] else {
      Issue.record("expected a visible block")
      return
    }
    #expect(visible.first?.text == "  fun waitForDisplay(")
    #expect(visible.last?.text == "  }")
  }

  @Test func singleLineFuncHeaderIsUnchanged() throws {
    let content = [
      "struct Padding {",
      "  func compute() -> Int {",
      "    let filler = 0",
      "    let value = 1",
      "    return value",
      "  }",
      "}",
    ].joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/padding.swift", fileContent: content, oldString: "    let value = 1",
        newString: "    let value = 2", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .visible(let visible) = diff.segments[1] else {
      Issue.record("expected a visible block")
      return
    }
    #expect(visible.first?.text == "  func compute() -> Int {")
    #expect(visible.last?.text == "  }")
  }

  @Test func elseHeaderWalksUpToItsIfLineAtTheSameIndent() throws {
    let content = [
      "struct Chooser {",
      "  func choose(_ flag: Bool) -> Int {",
      "    if flag {",
      "      let a = 1",
      "      return a",
      "    } else {",
      "      let value = 1",
      "      return value",
      "    }",
      "  }",
      "}",
    ].joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/chooser.swift", fileContent: content, oldString: "      let value = 1",
        newString: "      let value = 2", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .visible(let visible) = diff.segments[1] else {
      Issue.record("expected a visible block")
      return
    }
    #expect(visible.first?.text == "    if flag {")
    #expect(visible.last?.text == "    }")
  }

  @Test func extendedSignatureWalkBeyondSixtyLinesKeepsOriginalHeader() throws {
    var lines = ["final class Big {", "  func longSignature("]
    lines += (1...60).map { "    param\($0): Int," }
    lines.append("  ) -> Int {")
    lines.append("    let filler = 0")
    lines.append("    let value = 1")
    lines.append("    return value")
    lines.append("  }")
    lines.append("}")
    let content = lines.joined(separator: "\n")

    let diff = try #require(
      FileDiffBuilder.edit(
        path: "/tmp/big.swift", fileContent: content, oldString: "    let value = 1",
        newString: "    let value = 2", replaceAll: false))

    #expect(diff.segments.count == 3)
    guard case .visible(let visible) = diff.segments[1] else {
      Issue.record("expected a visible block")
      return
    }
    #expect(visible.first?.text == "  ) -> Int {")
    #expect(!visible.contains { $0.text == "  func longSignature(" })
  }

  @Test func finalNewlineNeverAddsAPhantomLineToAnEdit() {
    #expect(
      FileDiffBuilder.numberedDiff(old: "a\nb\n", new: "a\nc\n") == [
        NumberedLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
        NumberedLine(kind: .removed, text: "b", oldNumber: 2, newNumber: nil),
        NumberedLine(kind: .added, text: "c", oldNumber: nil, newNumber: 2),
      ])
  }

  @Test func lastLineShowsRemovedAndAddedWhenOnlyOneSideEndsWithNewline() {
    #expect(
      FileDiffBuilder.numberedDiff(old: "a\nb", new: "a\nb\n") == [
        NumberedLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
        NumberedLine(kind: .removed, text: "b", oldNumber: 2, newNumber: nil),
        NumberedLine(kind: .added, text: "b", oldNumber: nil, newNumber: 2),
      ])
  }

  @Test func writingIntoAnEmptyFileShowsOnlyTheAddedLines() {
    let diff = FileDiffBuilder.write(path: "/tmp/empty.txt", fileContent: "", newContent: "a\nb\n")
    #expect(diff.status == .modified)
    #expect(
      diff.segments == [
        .visible([
          NumberedLine(kind: .added, text: "a", oldNumber: nil, newNumber: 1),
          NumberedLine(kind: .added, text: "b", oldNumber: nil, newNumber: 2),
        ])
      ])
  }

  @Test func createdFileEndingWithNewlineHasNoPhantomLastLine() {
    let diff = FileDiffBuilder.write(path: "/tmp/new.txt", fileContent: nil, newContent: "a\nb\n")
    #expect(
      diff.segments == [
        .visible([
          NumberedLine(kind: .added, text: "a", oldNumber: nil, newNumber: 1),
          NumberedLine(kind: .added, text: "b", oldNumber: nil, newNumber: 2),
        ])
      ])
  }

  @Test func deletedFileEndingWithNewlineHasNoPhantomLastLine() throws {
    let file = PatchFile(operation: .delete, path: "Sources/Old.swift", movedTo: nil, lines: [])
    let content = (1...7).map { "line\($0)" }.joined(separator: "\n") + "\n"
    let diff = try #require(FileDiffBuilder.patch(file, fileContent: content))
    guard case .visible(let visible) = diff.segments.first else {
      Issue.record("expected a visible segment")
      return
    }
    #expect(diff.segments.count == 1)
    #expect(visible.count == 7)
    #expect(
      visible.last == NumberedLine(kind: .removed, text: "line7", oldNumber: 7, newNumber: nil))
  }

  @Test func applyingHunksKeepsTheFilesTrailingNewlineAsItIs() {
    let hunk: [DiffLine] = [
      DiffLine(kind: .context, text: "a"),
      DiffLine(kind: .removed, text: "b"),
      DiffLine(kind: .added, text: "c"),
    ]
    #expect(FileDiffBuilder.applyingHunks(hunk, to: "a\nb\n") == "a\nc\n")
    #expect(FileDiffBuilder.applyingHunks(hunk, to: "a\nb") == "a\nc")
    #expect(FileDiffBuilder.applyingHunks(hunk, to: "a\r\nb\r\n") == "a\nc\n")
    let removeAll: [DiffLine] = [DiffLine(kind: .removed, text: "a")]
    #expect(FileDiffBuilder.applyingHunks(removeAll, to: "a\n") == "")
  }

  @Test func codexUpdateOfFileEndingWithNewlineShowsNoNewlineChange() throws {
    let file = PatchFile(
      operation: .update, path: "Sources/A.swift", movedTo: nil,
      lines: [
        DiffLine(kind: .context, text: "a"),
        DiffLine(kind: .removed, text: "b"),
        DiffLine(kind: .added, text: "c"),
      ])
    let diff = try #require(FileDiffBuilder.patch(file, fileContent: "a\nb\nz\n"))
    let lines = diff.segments.flatMap { segment -> [NumberedLine] in
      switch segment {
      case .visible(let lines), .gap(let lines): return lines
      }
    }
    #expect(lines.map(\.text) == ["a", "b", "c", "z"])
    #expect(lines.filter { $0.kind != .context }.map(\.text) == ["b", "c"])
  }

  @Test func addedFileContentSkipsHunkSeparatorRows() throws {
    let file = PatchFile(
      operation: .add, path: "Sources/New.swift", movedTo: nil,
      lines: [DiffLine(kind: .collapsed, text: "anchor"), DiffLine(kind: .added, text: "x")])
    let diff = try #require(FileDiffBuilder.patch(file, fileContent: nil))
    #expect(
      diff.segments == [
        .visible([NumberedLine(kind: .added, text: "x", oldNumber: nil, newNumber: 1)])
      ])
  }

  @Test func hiddenRestOfCreatedAndDeletedFilesReadsAsMoreLines() throws {
    let content = (1...50).map { "line\($0)" }.joined(separator: "\n")
    let created = FileDiffBuilder.write(path: "/tmp/new.txt", fileContent: nil, newContent: content)
    let deleted = try #require(
      FileDiffBuilder.patch(
        PatchFile(operation: .delete, path: "/tmp/old.txt", movedTo: nil, lines: []),
        fileContent: content))
    for diff in [created, deleted] {
      guard case .gap(let hidden) = diff.segments.last else {
        Issue.record("expected the rest in a gap")
        continue
      }
      #expect(
        FileDiffBuilder.gapTitle(hiddenCount: hidden.count, of: hidden) == "Show 10 more lines")
      #expect(FileDiffBuilder.gapTitle(hiddenCount: 1, of: hidden) == "Show 1 more line")
    }
  }

  @Test func hiddenContextReadsAsUnchangedLines() {
    let context = [
      NumberedLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
      NumberedLine(kind: .context, text: "b", oldNumber: 2, newNumber: 2),
    ]
    #expect(FileDiffBuilder.gapTitle(hiddenCount: 2, of: context) == "Show 2 unchanged lines")
    #expect(FileDiffBuilder.gapTitle(hiddenCount: 1, of: context) == "Show 1 unchanged line")
  }

  @Test func numberedDiffAssignsLineNumbersForEveryKind() {
    let old = ["a", "b", "c", "d", "e"].joined(separator: "\n")
    let new = ["a", "c", "Z", "d", "f"].joined(separator: "\n")
    let numbered = FileDiffBuilder.numberedDiff(old: old, new: new)
    #expect(
      numbered == [
        NumberedLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
        NumberedLine(kind: .removed, text: "b", oldNumber: 2, newNumber: nil),
        NumberedLine(kind: .context, text: "c", oldNumber: 3, newNumber: 2),
        NumberedLine(kind: .added, text: "Z", oldNumber: nil, newNumber: 3),
        NumberedLine(kind: .context, text: "d", oldNumber: 4, newNumber: 4),
        NumberedLine(kind: .removed, text: "e", oldNumber: 5, newNumber: nil),
        NumberedLine(kind: .added, text: "f", oldNumber: nil, newNumber: 5),
      ])
  }

  @Test func displayPathIsRelativeInsideCwdAndTildeAbbreviatedOutsideIt() {
    #expect(
      FileDiffBuilder.computeDisplayPath("/a/b/c/file.swift", cwd: "/a/b/c") == "file.swift")
    #expect(
      FileDiffBuilder.computeDisplayPath("/a/b/c/nested/file.swift", cwd: "/a/b/c")
        == "nested/file.swift")

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(
      FileDiffBuilder.computeDisplayPath("\(home)/Notes/todo.txt", cwd: "/somewhere/else")
        == "~/Notes/todo.txt")
    #expect(
      FileDiffBuilder.computeDisplayPath("/outside/both/file.txt", cwd: "/a/b/c")
        == "/outside/both/file.txt")
  }

  @Test func loadBuildsDiffForClaudeEditFromRealFile() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("Widget.swift")
    let content = ["func widget() -> Int {", "  let value = 1", "  return value", "}"].joined(
      separator: "\n")
    try content.write(to: file, atomically: true, encoding: .utf8)

    let request = makeEditRequest(
      cwd: directory.path, path: file.path, oldString: "  let value = 1",
      newString: "  let value = 2")
    let diffs = try #require(FileDiffBuilder.load(for: request))
    #expect(diffs.count == 1)
    #expect(diffs[0].displayPath == "Widget.swift")
    #expect(diffs[0].status == .modified)
  }

  @Test func loadBuildsDiffForClaudeWriteFromRealFile() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("New.swift")

    let request = makeWriteRequest(cwd: directory.path, path: file.path, content: "let x = 1")
    let diffs = try #require(FileDiffBuilder.load(for: request))
    #expect(diffs.count == 1)
    #expect(diffs[0].status == .created)
    #expect(diffs[0].displayPath == "New.swift")
  }

  @Test func loadResolvesCodexPatchRelativePathsAgainstCwd() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("Checkout.swift")
    let content = ["func total() -> Int {", "  let value = 1", "  return value", "}"].joined(
      separator: "\n")
    try content.write(to: target, atomically: true, encoding: .utf8)

    let patchText = [
      "*** Begin Patch",
      "*** Update File: Checkout.swift",
      "@@ func total() -> Int {",
      "   let value = 1",
      "-  return value",
      "+  return value * 2",
      " *** End of File",
      "*** End Patch",
    ].joined(separator: "\n")
    let request = makePatchRequest(cwd: directory.path, patchText: patchText)
    let diffs = try #require(FileDiffBuilder.load(for: request))
    #expect(diffs.count == 1)
    #expect(diffs[0].path == target.path)
    #expect(diffs[0].displayPath == "Checkout.swift")
  }

  @Test func loadReturnsNilForNonUTF8FileContent() throws {
    let directory = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("Binary.swift")
    let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
    try invalidUTF8.write(to: file)

    let request = makeEditRequest(
      cwd: directory.path, path: file.path, oldString: "anything", newString: "else")
    #expect(FileDiffBuilder.load(for: request) == nil)
  }

  @Test func editReturnsNilWhenFileExceedsLineGuard() {
    let content = (1...20_001).map { "line\($0)" }.joined(separator: "\n")
    let diff = FileDiffBuilder.edit(
      path: "/tmp/huge.swift", fileContent: content, oldString: "line1", newString: "line1updated",
      replaceAll: false)
    #expect(diff == nil)
  }
}
