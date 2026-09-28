import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ConfigFileStarterTests {
  private func temporaryHome() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-starter-\(UUID().uuidString)")
  }

  private static var schemaURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/config.schema.json")
  }

  @Test func contentsAreExactlyTheSchemaReference() {
    #expect(
      ConfigFileStarter.contents
        == "{\n  \"$schema\": \"https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json\"\n}\n"
    )
  }

  @Test func contentsParseToAllDefaultsWithoutLogLines() {
    let (file, logLines) = ConfigFileParser.parse(Data(ConfigFileStarter.contents.utf8))
    #expect(file == ConfigFile())
    #expect(logLines.isEmpty)
  }

  @Test func schemaReferenceMatchesTheSchemasOwnID() throws {
    let starter = try JSONDecoder().decode(
      JSONValue.self, from: Data(ConfigFileStarter.contents.utf8))
    let schema = try JSONDecoder().decode(
      JSONValue.self, from: Data(contentsOf: Self.schemaURL))
    guard case .object(let starterObject) = starter, case .object(let schemaObject) = schema
    else {
      Issue.record("expected two JSON objects")
      return
    }
    let reference = try #require(starterObject["$schema"]?.stringValue)
    #expect(reference == schemaObject["$id"]?.stringValue)
  }

  @Test func createsTheDirectoryAndTheFile() throws {
    let home = temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = AppPaths(home: home)

    #expect(try ConfigFileStarter.createIfMissing(paths: paths))

    let written = try String(contentsOf: paths.configFile, encoding: .utf8)
    #expect(written == ConfigFileStarter.contents)
  }

  @Test func createsTheFileUnderXDGConfigHome() throws {
    let home = temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = AppPaths(home: home, xdgConfigHome: home.appendingPathComponent("xdg").path)

    #expect(try ConfigFileStarter.createIfMissing(paths: paths))

    #expect(paths.configFile.path.hasSuffix("/xdg/countersign/config.json"))
    #expect(FileManager.default.fileExists(atPath: paths.configFile.path))
  }

  @Test func leavesAnExistingFileAlone() throws {
    let home = temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = AppPaths(home: home)
    try FileManager.default.createDirectory(
      at: paths.configDirectory, withIntermediateDirectories: true)
    let existing = Data("{\"idleSeconds\": 9}".utf8)
    try existing.write(to: paths.configFile)

    #expect(try !ConfigFileStarter.createIfMissing(paths: paths))

    #expect(try Data(contentsOf: paths.configFile) == existing)
  }

  @Test func throwsWhenTheDirectoryCannotBeCreated() throws {
    let home = temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try Data("not a directory".utf8).write(to: home.appendingPathComponent(".config"))
    let paths = AppPaths(home: home)

    #expect(throws: (any Error).self) {
      try ConfigFileStarter.createIfMissing(paths: paths)
    }
    #expect(!FileManager.default.fileExists(atPath: paths.configFile.path))
  }
}
