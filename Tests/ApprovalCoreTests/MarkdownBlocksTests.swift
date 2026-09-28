import Foundation
import Testing

@testable import ApprovalCore

@Suite struct MarkdownBlocksTests {
  @Test func parsesFixturePlan() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-plan"))
    guard case .plan(let plan) = request.kind else {
      Issue.record("expected plan")
      return
    }
    let blocks = MarkdownBlocks.parse(plan.plan)

    guard case .heading(let level, let text) = blocks[0] else {
      Issue.record("expected heading")
      return
    }
    #expect(level == 1)
    #expect(text == "Add discount code support")

    guard
      let codeBlock = blocks.first(where: {
        if case .code = $0 { return true }
        return false
      }),
      case .code(let language, let codeText) = codeBlock
    else {
      Issue.record("expected code block")
      return
    }
    #expect(language == "swift")
    #expect(codeText.contains("func applyDiscount"))

    let bulletCount = blocks.filter {
      if case .bullet = $0 { return true }
      return false
    }.count
    #expect(bulletCount == 3)

    let numberedCount = blocks.filter {
      if case .numbered = $0 { return true }
      return false
    }.count
    #expect(numberedCount == 3)
  }

  @Test func headingLevels() {
    let blocks = MarkdownBlocks.parse("# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six")
    let levels = blocks.compactMap { block -> Int? in
      if case .heading(let level, _) = block { return level }
      return nil
    }
    #expect(levels == [1, 2, 3, 4, 5, 6])
  }

  @Test func nestedBullets() {
    let markdown = "- top\n  - nested\n    - deeper"
    let blocks = MarkdownBlocks.parse(markdown)
    #expect(
      blocks == [
        .bullet(indent: 0, text: "top"),
        .bullet(indent: 1, text: "nested"),
        .bullet(indent: 2, text: "deeper"),
      ])
  }

  @Test func numberedItems() {
    let blocks = MarkdownBlocks.parse("1. first\n2) second")
    #expect(
      blocks == [
        .numbered(indent: 0, number: "1", text: "first"),
        .numbered(indent: 0, number: "2", text: "second"),
      ])
  }

  @Test func rules() {
    let blocks = MarkdownBlocks.parse("---\n***\n___")
    #expect(blocks == [.rule, .rule, .rule])
  }

  @Test func paragraphsJoinConsecutiveLinesAndSplitOnBlankLines() {
    let blocks = MarkdownBlocks.parse("line one\nline two\n\nline three")
    #expect(
      blocks == [
        .paragraph(text: "line one\nline two"),
        .paragraph(text: "line three"),
      ])
  }

  @Test func unterminatedFenceRunsToEnd() {
    let blocks = MarkdownBlocks.parse("```swift\nlet a = 1\nlet b = 2")
    #expect(blocks == [.code(language: "swift", text: "let a = 1\nlet b = 2")])
  }

  @Test func fenceWithoutLanguage() {
    let blocks = MarkdownBlocks.parse("```\nplain\n```")
    #expect(blocks == [.code(language: nil, text: "plain")])
  }
}
