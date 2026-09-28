import Foundation
import Testing

@testable import ApprovalCore

private func layout(of text: String) throws -> JSONLayout {
  let bytes = Array(text.utf8)
  return JSONLayout.detect(in: bytes, root: try JSONSpanReader.parse(bytes))
}

@Suite struct JSONLayoutTests {
  @Test func detectsTwoSpacesAndLineFeeds() throws {
    let detected = try layout(of: "{\n  \"a\": {\n    \"b\": 1\n  }\n}\n")
    #expect(detected == .standard)
  }

  @Test func detectsFourSpaces() throws {
    #expect(try layout(of: "{\n    \"a\": 1\n}").indentUnit == "    ")
  }

  @Test func detectsTabs() throws {
    #expect(try layout(of: "{\n\t\"a\": [\n\t\t1\n\t]\n}").indentUnit == "\t")
  }

  @Test func detectsCarriageReturnLineFeeds() throws {
    #expect(try layout(of: "{\r\n  \"a\": 1\r\n}\r\n").newline == "\r\n")
    #expect(try layout(of: "{\n  \"a\": \"\\r\"\n}").newline == "\n")
  }

  @Test func detectsKeyAndColonSpacing() throws {
    let detected = try layout(of: "{\n  \"a\" : 1\n}")
    #expect(detected.beforeColon == " ")
    #expect(detected.afterColon == " ")
    let compact = try layout(of: "{\"a\":1}")
    #expect(compact.beforeColon == "")
    #expect(compact.afterColon == "")
  }

  @Test func findsTheFirstMemberInsideArrays() throws {
    let detected = try layout(of: "[[], {\"a\" :1}]")
    #expect(detected.beforeColon == " ")
    #expect(detected.afterColon == "")
  }

  @Test func ignoresColonSpacingThatBreaksALine() throws {
    let detected = try layout(of: "{\n  \"a\":\n    1\n}")
    #expect(detected.beforeColon == "")
    #expect(detected.afterColon == " ")
  }

  @Test func findsTheIndentUnitDeeperWhenTheTopLevelIsOnOneLine() throws {
    #expect(try layout(of: "{\"a\": [\n   1\n]}").indentUnit == "   ")
    #expect(try layout(of: "[1, {\n    \"a\": 1\n}]").indentUnit == "    ")
  }

  @Test func fallsBackToTheStandardLayout() throws {
    #expect(try layout(of: "{}") == .standard)
    #expect(try layout(of: "{\"a\": [1, 2]}").indentUnit == "  ")
    #expect(try layout(of: "\"text\"") == .standard)
    #expect(try layout(of: "{\n\"a\": 1\n}").indentUnit == "  ")
  }

  @Test func readsTheIndentOfALine() {
    let bytes = Array("{\n  \t\"a\": 1\n}".utf8)
    #expect(JSONLayout.lineIndent(in: bytes, at: 5) == "  \t")
    #expect(JSONLayout.lineIndent(in: bytes, at: 0) == "")
    #expect(JSONLayout.lineIndent(in: bytes, at: bytes.count) == "")
  }

  @Test func escapesStrings() {
    #expect(JSONLayout.quoted("plain") == "\"plain\"")
    #expect(
      JSONLayout.escaped("\" \\ \n \r \t \u{08} \u{0C} \u{01} \u{1F} / é")
        == "\\\" \\\\ \\n \\r \\t \\b \\f \\u0001 \\u001f / é")
  }

  @Test func rendersFragmentsWithTheLayout() {
    let fragment = JSONFragment.object([
      JSONFragmentMember(key: "matcher", value: .string("")),
      JSONFragmentMember(key: "hooks", value: .array([.integer(1), .array([]), .object([])])),
    ])
    let tabs = JSONLayout(indentUnit: "\t", newline: "\r\n", beforeColon: " ", afterColon: " ")
    #expect(
      tabs.render(fragment, indent: "\t")
        == "{\r\n\t\t\"matcher\" : \"\",\r\n\t\t\"hooks\" : [\r\n\t\t\t1,\r\n\t\t\t[],\r\n\t\t\t{}\r\n\t\t]\r\n\t}"
    )
    #expect(
      JSONLayout.standard.memberText(
        JSONFragmentMember(key: "timeout", value: .integer(3600)), indent: "")
        == "\"timeout\": 3600")
  }

  @Test func rendersANumberAsItIsSpelled() {
    #expect(JSONLayout.standard.render(.number("0.5"), indent: "") == "0.5")
    #expect(JSONLayout.standard.render(.number("1e3"), indent: "  ") == "1e3")
  }

  @Test func rendersBooleans() {
    #expect(JSONLayout.standard.render(.bool(true), indent: "") == "true")
    #expect(JSONLayout.standard.render(.bool(false), indent: "  ") == "false")
  }
}
