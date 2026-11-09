import Foundation
import Testing

@testable import ApprovalCore

@Suite struct PreferenceFileWriterTests {
  @Test func createsTheFileAndALaterIdenticalApplyLeavesTheBytesAlone() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-preference-writer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("nested").appendingPathComponent("config.json")
    try PreferenceFileWriter.apply([.idleSeconds(7)], configFile: file)
    let first = try Data(contentsOf: file)
    #expect(ConfigFileParser.parse(first).file.idleSeconds == 7)
    try PreferenceFileWriter.apply([.idleSeconds(7)], configFile: file)
    #expect(try Data(contentsOf: file) == first)
    let backups = try FileManager.default.contentsOfDirectory(
      atPath: file.deletingLastPathComponent().path
    ).filter { $0.hasSuffix(".bak") }
    #expect(backups.isEmpty)
  }
}
