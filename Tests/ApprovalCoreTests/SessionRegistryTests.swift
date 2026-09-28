import Foundation
import Testing

@testable import ApprovalCore

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func writeRegistryFile(
  at url: URL,
  fields: [String: JSONValue]
) throws {
  let data = try JSONEncoder().encode(JSONValue.object(fields))
  try data.write(to: url)
}

private func setModificationDate(_ date: Date, on url: URL) throws {
  try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

@Suite struct SessionRegistryTests {
  @Test func findsEntryMatchingSessionID() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("100.json")
    try writeRegistryFile(
      at: url, fields: ["sessionId": .string("s1"), "kind": .string("interactive")])
    let entry = SessionRegistry.findEntry(sessionID: "s1", in: dir)
    #expect(entry?.url.lastPathComponent == url.lastPathComponent)
    #expect(entry?.fields["kind"]?.stringValue == "interactive")
  }

  @Test func returnsNilWhenNoFileMatches() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("100.json")
    try writeRegistryFile(at: url, fields: ["sessionId": .string("other")])
    #expect(SessionRegistry.findEntry(sessionID: "s1", in: dir) == nil)
  }

  @Test func ignoresKeyFilesEvenWhenTheyWouldMatch() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("100.key")
    try writeRegistryFile(at: url, fields: ["sessionId": .string("s1")])
    #expect(SessionRegistry.findEntry(sessionID: "s1", in: dir) == nil)
  }

  @Test func returnsNilForTruncatedJSON() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("100.json")
    try Data("{\"sessionId\":\"s1\"".utf8).write(to: url)
    #expect(SessionRegistry.findEntry(sessionID: "s1", in: dir) == nil)
  }

  @Test func returnsNilWhenDirectoryIsMissing() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(SessionRegistry.findEntry(sessionID: "s1", in: dir) == nil)
  }

  @Test func picksTheNewestMatchingFile() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let olderURL = dir.appendingPathComponent("200.json")
    let newerURL = dir.appendingPathComponent("201.json")
    try writeRegistryFile(
      at: olderURL, fields: ["sessionId": .string("s1"), "kind": .string("interactive")])
    try setModificationDate(Date(timeIntervalSince1970: 1000), on: olderURL)
    try writeRegistryFile(
      at: newerURL, fields: ["sessionId": .string("s1"), "kind": .string("headless")])
    try setModificationDate(Date(timeIntervalSince1970: 2000), on: newerURL)
    let entry = SessionRegistry.findEntry(sessionID: "s1", in: dir)
    #expect(entry?.url.lastPathComponent == newerURL.lastPathComponent)
    #expect(entry?.fields["kind"]?.stringValue == "headless")
  }
}
