import Foundation
import Testing

@testable import ApprovalCore

@Suite struct JSONValuePrettyTests {
  @Test func prettyPrintsKeysInSortedOrder() {
    let value = JSONValue.object([
      "zebra": .string("z"),
      "alpha": .int(1),
      "middle": .bool(true),
    ])
    let printed = value.prettyPrinted
    let alphaRange = printed.range(of: "\"alpha\"")
    let middleRange = printed.range(of: "\"middle\"")
    let zebraRange = printed.range(of: "\"zebra\"")
    if let alphaRange, let middleRange, let zebraRange {
      #expect(alphaRange.lowerBound < middleRange.lowerBound)
      #expect(middleRange.lowerBound < zebraRange.lowerBound)
    } else {
      Issue.record("expected all three keys to appear in the pretty-printed output")
    }
  }

  @Test func prettyPrintsWithIndentation() {
    let value = JSONValue.object(["a": .array([.int(1), .int(2)])])
    let printed = value.prettyPrinted
    #expect(printed.contains("\n"))
    #expect(printed.contains("  "))
  }

  @Test func prettyPrintsWithoutEscapingSlashes() {
    let value = JSONValue.string("https://example.com/path")
    let printed = value.prettyPrinted
    #expect(printed == "\"https://example.com/path\"")
  }

  @Test func prettyPrintsNullDirectly() {
    let value = JSONValue.null
    #expect(value.prettyPrinted == "null")
  }

  @Test func prettyPrintsIntegersWithoutDecimalPoint() {
    let value = JSONValue.object(["count": .int(50)])
    #expect(value.prettyPrinted.contains("50") == true)
    #expect(value.prettyPrinted.contains("50.0") == false)
  }
}
