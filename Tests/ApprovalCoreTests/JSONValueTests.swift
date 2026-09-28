import Foundation
import Testing

@testable import ApprovalCore

@Suite struct JSONValueTests {
  @Test func roundTripsBool() throws {
    let data = Data("true".utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(value == .bool(true))
    let encoded = try JSONEncoder().encode(value)
    #expect(String(data: encoded, encoding: .utf8) == "true")
  }

  @Test func roundTripsInt() throws {
    let data = Data("1".utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(value == .int(1))
    let encoded = try JSONEncoder().encode(value)
    #expect(String(data: encoded, encoding: .utf8) == "1")
  }

  @Test func roundTripsDouble() throws {
    let data = Data("1.5".utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(value == .double(1.5))
    let encoded = try JSONEncoder().encode(value)
    #expect(String(data: encoded, encoding: .utf8) == "1.5")
  }

  @Test func roundTripsNull() throws {
    let data = Data("null".utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(value == .null)
  }

  @Test func roundTripsNestedStructure() throws {
    let json = """
      {"name":"test","count":3,"ratio":0.5,"tags":["a","b"],"active":true,"meta":null}
      """
    let data = Data(json.utf8)
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    guard case .object(let object) = value else {
      Issue.record("expected object")
      return
    }
    #expect(object["name"] == .string("test"))
    #expect(object["count"] == .int(3))
    #expect(object["ratio"] == .double(0.5))
    #expect(object["tags"] == .array([.string("a"), .string("b")]))
    #expect(object["active"] == .bool(true))
    #expect(object["meta"] == .null)
  }

  @Test func subscriptAndAccessors() {
    let value = JSONValue.object([
      "key": .string("value"),
      "flag": .bool(true),
      "items": .array([.int(1)]),
    ])
    #expect(value["key"]?.stringValue == "value")
    #expect(value["flag"]?.boolValue == true)
    #expect(value["items"]?.arrayValue?.count == 1)
    #expect(value["missing"] == nil)
    #expect(JSONValue.string("x")["key"] == nil)
    #expect(value.objectValue?["key"] == .string("value"))
  }
}
