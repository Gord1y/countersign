import Foundation
import Testing

@testable import ApprovalCore

private func parse(_ text: String) throws -> JSONSpanNode {
  try JSONSpanReader.parse(Array(text.utf8))
}

private func source(_ text: String, _ range: Range<Int>) -> String {
  String(decoding: Array(text.utf8)[range], as: UTF8.self)
}

private let lineComment = String(repeating: "/", count: 2) + " note"
private let blockComment = "/" + "* note *" + "/"

@Suite struct JSONSpanTests {
  @Test func recordsTheSourceRangeOfEveryValue() throws {
    let text = "{\"a\": [1, true], \"b\" : {\"c\": null}}"
    let root = try parse(text)
    #expect(root.range == 0..<text.utf8.count)
    let members = try #require(root.members)
    #expect(members.map(\.key) == ["a", "b"])
    #expect(source(text, members[0].keyRange) == "\"a\"")
    #expect(source(text, members[0].value.range) == "[1, true]")
    #expect(source(text, members[0].range) == "\"a\": [1, true]")
    let elements = try #require(members[0].value.elements)
    #expect(elements.map { source(text, $0.range) } == ["1", "true"])
    #expect(elements[1].content == .bool(true))
    #expect(source(text, members[1].value.range) == "{\"c\": null}")
    #expect(members[1].value.member(named: "c")?.value.content == .null)
  }

  @Test func readsEveryScalarKind() throws {
    let root = try parse("[\"text\", -12.5e+3, 0, false, null, {}, []]")
    let elements = try #require(root.elements)
    #expect(elements[0].stringValue == "text")
    #expect(elements[1].content == .number("-12.5e+3"))
    #expect(elements[1].numberValue == -12500)
    #expect(elements[2].numberValue == 0)
    #expect(elements[3].content == .bool(false))
    #expect(elements[4].content == .null)
    #expect(elements[5].members == [])
    #expect(elements[6].elements == [])
  }

  @Test func keepsTheNumberSpellingAsWritten() throws {
    let root = try parse("{\"timeout\": 3.6E3}")
    let value = try #require(root.member(named: "timeout")?.value)
    #expect(value.content == .number("3.6E3"))
    #expect(value.numberValue == 3600)
    #expect(value.stringValue == nil)
    #expect(value.members == nil)
    #expect(value.elements == nil)
  }

  @Test func decodesEscapesAndUnicode() throws {
    let root = try parse(
      "{\"k\\u0065y\": \"caf\\u00e9 \\ud83d\\ude00 \\\" \\\\ \\/ \\b\\f\\n\\r\\t é\"}")
    let member = try #require(root.members?.first)
    #expect(member.key == "key")
    #expect(member.value.stringValue == "café 😀 \" \\ / \u{08}\u{0C}\n\r\t é")
  }

  @Test func replacesALoneSurrogateWithTheReplacementCharacter() throws {
    #expect(try parse("\"\\ud83d\"").stringValue == "\u{FFFD}")
    #expect(try parse("\"\\ud83d\\u0041\"").stringValue == "\u{FFFD}A")
    #expect(try parse("\"\\ude00\"").stringValue == "\u{FFFD}")
  }

  @Test func usesTheLastOfDuplicateKeys() throws {
    let root = try parse("{\"a\": 1, \"a\": 2}")
    #expect(root.member(named: "a")?.value.numberValue == 2)
    #expect(root.memberIndex(named: "a") == 1)
    #expect(root.member(named: "missing") == nil)
    #expect(root.memberIndex(named: "missing") == nil)
  }

  @Test func acceptsSurroundingWhitespaceOfEveryKind() throws {
    let root = try parse(" \t\r\n{\r\n\t\"a\"\t:\t1\r\n}\r\n ")
    #expect(root.member(named: "a")?.value.numberValue == 1)
  }

  @Test func rejectsWhatIsNotJSON() {
    let invalid = [
      "", "   ", "{", "}", "{\"a\": 1,}", "[1,]", "{\"a\" 1}", "{a: 1}", "{\"a\": 1} {}",
      lineComment + "\n{}", "{\n  " + lineComment + "\n  \"a\": 1\n}",
      "{\"a\": " + blockComment + " 1}", "{'a': 1}",
      "[01]", "[1.]", "[.5]", "[1e]", "[-]", "[+1]", "[tru]", "[nul]", "[\"\\x\"]",
      "[\"\\u12\"]", "[\"a\nb\"]", "[\"unterminated]", "\u{FEFF}{}", "{\"a\": NaN}",
    ]
    for text in invalid {
      #expect(throws: JSONSpanError.self, "\(text.debugDescription)") { try parse(text) }
    }
  }

  @Test func rejectsMalformedUTF8InsideStrings() {
    let samples: [[UInt8]] = [
      [0x22, 0xC3, 0x22],
      [0x22, 0xC0, 0xAF, 0x22],
      [0x22, 0xE0, 0x80, 0x80, 0x22],
      [0x22, 0xED, 0xA0, 0x80, 0x22],
      [0x22, 0xF5, 0x80, 0x80, 0x80, 0x22],
      [0x22, 0x80, 0x22],
      [0x22, 0xE2, 0x82],
    ]
    for bytes in samples {
      #expect(throws: JSONSpanError.self) { try JSONSpanReader.parse(bytes) }
    }
  }

  @Test func readsMultiByteUTF8() throws {
    let bytes: [UInt8] = [0x22, 0x61, 0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80, 0x22]
    #expect(try JSONSpanReader.parse(bytes).stringValue == "aé€😀")
  }

  @Test func reportsTheLineAndColumnOfTheFailure() {
    #expect(throws: JSONSpanError(line: 3, column: 3)) {
      try parse("{\n  \"a\": 1,\n  " + lineComment + "\n}")
    }
    #expect(throws: JSONSpanError(line: 1, column: 1)) { try parse("") }
    #expect(JSONSpanError(line: 2, column: 5).description == "not valid JSON at line 2, column 5")
  }

  @Test func limitsTheNestingDepth() throws {
    let limit = JSONSpanReader.maximumDepth
    let deepest = String(repeating: "[", count: limit) + String(repeating: "]", count: limit)
    #expect(try parse(deepest).elements?.count == 1)
    let tooDeep = "[" + deepest + "]"
    #expect(throws: JSONSpanError(line: 1, column: limit + 1)) { try parse(tooDeep) }
    let hostile = String(repeating: "{\"a\":", count: 100_000)
    #expect(throws: JSONSpanError.self) { try parse(hostile) }
  }

  @Test func classifiesWhitespaceBytes() {
    #expect(JSONByte.isWhitespace(UInt8(ascii: " ")))
    #expect(JSONByte.isWhitespace(UInt8(ascii: "\t")))
    #expect(JSONByte.isWhitespace(UInt8(ascii: "\n")))
    #expect(JSONByte.isWhitespace(UInt8(ascii: "\r")))
    #expect(!JSONByte.isWhitespace(UInt8(ascii: "x")))
    #expect(!JSONByte.isWhitespace(0x0B))
  }
}
