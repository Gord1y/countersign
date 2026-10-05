import Foundation
import Testing

@testable import ApprovalCore

@Suite struct RuleFileWriterTests {
  private func freshFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-rule-writer-\(UUID().uuidString)")
      .appendingPathComponent("nested")
      .appendingPathComponent("config.json")
  }

  private func parsed(_ file: URL) throws -> ConfigFile {
    ConfigFileParser.parse(try Data(contentsOf: file)).file
  }

  private let rules = [
    ApprovalRule(
      decision: .allow, agent: .cursor, project: "~/code/shop", command: "pnpm lint"),
    ApprovalRule(decision: .allow, agent: .codex, project: "~/code/shop", tool: "apply_patch"),
  ]

  @Test func createsTheMissingDirectoryAndRoundTripsTheRules() throws {
    let file = freshFile()
    defer {
      try? FileManager.default.removeItem(
        at: file.deletingLastPathComponent().deletingLastPathComponent())
    }
    try RuleFileWriter.add(rules, configFile: file)
    #expect(try parsed(file).rules == rules)
  }

  @Test func appendsToAnExistingFileAndBacksItUp() throws {
    let file = freshFile()
    let directory = file.deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    try RuleFileWriter.add([rules[0]], configFile: file)
    try RuleFileWriter.add(rules, configFile: file)
    #expect(try parsed(file).rules == rules)
    let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasSuffix(".bak") }
    #expect(backups.count == 1)
  }
}
