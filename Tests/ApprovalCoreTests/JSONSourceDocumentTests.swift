import Foundation
import Testing

@testable import ApprovalCore

private func document(_ text: String) throws -> JSONSourceDocument {
  try JSONSourceDocument(bytes: Array(text.utf8))
}

private func text(_ document: JSONSourceDocument) -> String {
  String(decoding: document.bytes, as: UTF8.self)
}

private let flag = JSONFragmentMember(key: "flag", value: .integer(1))

@Suite struct JSONSourceDocumentTests {
  @Test func appendsAMemberOnItsOwnLineWithTheSameIndent() throws {
    var edited = try document("{\n    \"a\": 1,\n\n    \"b\": 2\n}\n")
    try edited.appendMember(flag, to: edited.root)
    #expect(text(edited) == "{\n    \"a\": 1,\n\n    \"b\": 2,\n    \"flag\": 1\n}\n")
  }

  @Test func appendsANestedValueExpandedBelowTheLastMember() throws {
    var edited = try document("{\n  \"a\": 1\n}")
    let nested = JSONFragmentMember(key: "list", value: .array([.string("x")]))
    try edited.appendMember(nested, to: edited.root)
    #expect(text(edited) == "{\n  \"a\": 1,\n  \"list\": [\n    \"x\"\n  ]\n}")
  }

  @Test func appendsOnTheSameLineWhenTheObjectIsOnOneLine() throws {
    var spaced = try document("{ \"a\": 1 }")
    try spaced.appendMember(flag, to: spaced.root)
    #expect(text(spaced) == "{ \"a\": 1, \"flag\": 1 }")
    var compact = try document("{\"a\":1}")
    try compact.appendMember(flag, to: compact.root)
    #expect(text(compact) == "{\"a\":1,\"flag\":1}")
  }

  @Test func expandsAnEmptyObject() throws {
    var empty = try document("{}")
    try empty.appendMember(flag, to: empty.root)
    #expect(text(empty) == "{\n  \"flag\": 1\n}")
    var spaced = try document("{ \n }\n")
    try spaced.appendMember(flag, to: spaced.root)
    #expect(text(spaced) == "{\n  \"flag\": 1\n}\n")
  }

  @Test func expandsAnEmptyNestedContainerFromItsLineIndent() throws {
    var edited = try document("{\r\n\t\"a\": []\r\n}")
    let array = try #require(edited.root.member(named: "a")?.value)
    try edited.appendElement(.object([flag]), to: array)
    #expect(text(edited) == "{\r\n\t\"a\": [\r\n\t\t{\r\n\t\t\t\"flag\": 1\r\n\t\t}\r\n\t]\r\n}")
  }

  @Test func appendsAnElementAfterTheLastOne() throws {
    var edited = try document("[\n  1,\n  2\n]")
    try edited.appendElement(.integer(3), to: edited.root)
    #expect(text(edited) == "[\n  1,\n  2,\n  3\n]")
  }

  @Test func removesTheFirstMiddleAndLastChild() throws {
    var first = try document("[\n  1,\n  2,\n  3\n]")
    try first.removeElement(at: 0, from: first.root)
    #expect(text(first) == "[\n  2,\n  3\n]")
    var middle = try document("[\n  1,\n  2,\n  3\n]")
    try middle.removeElement(at: 1, from: middle.root)
    #expect(text(middle) == "[\n  1,\n  3\n]")
    var last = try document("{\"a\": 1, \"b\": 2}")
    try last.removeMember(at: 1, from: last.root)
    #expect(text(last) == "{\"a\": 1}")
  }

  @Test func removingTheOnlyChildLeavesAnEmptyContainer() throws {
    var edited = try document("{\n  \"a\": {\n    \"b\": 1\n  }\n}\n")
    let inner = try #require(edited.root.member(named: "a")?.value)
    try edited.removeMember(at: 0, from: inner)
    #expect(text(edited) == "{\n  \"a\": {}\n}\n")
  }

  @Test func replacesAValueInPlace() throws {
    var edited = try document("{\"timeout\": 600, \"b\": \"\\u0041\"}")
    let timeout = try #require(edited.root.member(named: "timeout")?.value)
    try edited.replaceValue(timeout, with: .integer(3600))
    #expect(text(edited) == "{\"timeout\": 3600, \"b\": \"\\u0041\"}")
  }

  @Test func reparsesAfterEveryEdit() throws {
    var edited = try document("{\"a\": 1}")
    try edited.replace(1..<4, with: "\"key\"")
    #expect(edited.root.member(named: "key")?.value.numberValue == 1)
    #expect(throws: JSONSpanError.self) { try edited.replace(0..<1, with: "[") }
    #expect(text(edited) == "{\"key\": 1}")
  }

  @Test func refusesToEditWhatIsNotAContainer() throws {
    var edited = try document("{\"a\": 1}")
    let number = try #require(edited.root.member(named: "a")?.value)
    #expect(throws: JSONEditError.notAContainer) { try edited.appendMember(flag, to: number) }
    #expect(throws: JSONEditError.notAContainer) {
      try edited.appendElement(.integer(1), to: number)
    }
    #expect(throws: JSONEditError.notAContainer) { try edited.removeMember(at: 0, from: number) }
    #expect(throws: JSONEditError.notAContainer) { try edited.removeElement(at: 0, from: number) }
    #expect(throws: JSONEditError.childOutOfRange) {
      try edited.removeMember(at: 1, from: edited.root)
    }
  }

  @Test func readsTheIndentOfAnOffset() throws {
    let edited = try document("{\n   \"a\": 1\n}")
    #expect(edited.lineIndent(at: 5) == "   ")
    #expect(edited.layout.indentUnit == "   ")
  }
}
