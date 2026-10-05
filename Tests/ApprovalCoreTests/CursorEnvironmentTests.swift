import Foundation
import SQLite3
import Testing

@testable import ApprovalCore

private func fixtureValue() throws -> JSONValue {
  try JSONDecoder().decode(
    JSONValue.self, from: FixtureLoader.data("cursor-state-application-user"))
}

private func replacingAgent(
  in root: JSONValue, with agent: [String: JSONValue]?, runEverything: Bool? = nil
) -> JSONValue {
  guard var rootObject = root.objectValue,
    var composerState = root["composerState"]?.objectValue,
    var modes = root["composerState"]?["modes4"]?.arrayValue
  else { return root }
  modes.removeAll { $0["id"]?.stringValue == "agent" }
  if let agent { modes.insert(.object(agent), at: 0) }
  composerState["modes4"] = .array(modes)
  if let runEverything { composerState["yoloEnableRunEverything"] = .bool(runEverything) }
  rootObject["composerState"] = .object(composerState)
  return .object(rootObject)
}

private func agentEntry(
  autoRun: JSONValue?, fullAutoRun: JSONValue?, smartModeAutoRun: JSONValue?
) -> [String: JSONValue] {
  var entry: [String: JSONValue] = ["id": .string("agent"), "name": .string("Agent")]
  entry["autoRun"] = autoRun
  entry["fullAutoRun"] = fullAutoRun
  entry["smartModeAutoRun"] = smartModeAutoRun
  return entry
}

@Suite struct CursorRunModeTests {
  @Test func resolvesTheFixtureAsAutoReview() throws {
    #expect(CursorRunMode.resolve(applicationUser: try fixtureValue()) == .autoReview)
  }

  @Test func missingAgentEntryIsUnknown() throws {
    let value = replacingAgent(in: try fixtureValue(), with: nil)
    #expect(CursorRunMode.resolve(applicationUser: value) == .unknown)
  }

  @Test func autoRunThatIsNotABoolIsUnknown() throws {
    let entry = agentEntry(
      autoRun: .string("true"), fullAutoRun: .bool(false), smartModeAutoRun: .bool(true))
    let value = replacingAgent(in: try fixtureValue(), with: entry)
    #expect(CursorRunMode.resolve(applicationUser: value) == .unknown)
  }

  @Test func autoRunFalseAsksEveryTime() throws {
    let entry = agentEntry(autoRun: .bool(false), fullAutoRun: nil, smartModeAutoRun: nil)
    let value = replacingAgent(in: try fixtureValue(), with: entry)
    #expect(CursorRunMode.resolve(applicationUser: value) == .asksEveryTime)
  }

  @Test func missingSmartModeAutoRunIsUnknown() throws {
    let entry = agentEntry(
      autoRun: .bool(true), fullAutoRun: .bool(false), smartModeAutoRun: nil)
    let value = replacingAgent(in: try fixtureValue(), with: entry)
    #expect(CursorRunMode.resolve(applicationUser: value) == .unknown)
  }

  @Test func missingFullAutoRunIsUnknown() throws {
    let entry = agentEntry(
      autoRun: .bool(true), fullAutoRun: nil, smartModeAutoRun: .bool(true))
    let value = replacingAgent(in: try fixtureValue(), with: entry)
    #expect(CursorRunMode.resolve(applicationUser: value) == .unknown)
  }

  @Test func fullAutoRunIsRunEverything() throws {
    let entry = agentEntry(
      autoRun: .bool(true), fullAutoRun: .bool(true), smartModeAutoRun: .bool(false))
    let value = replacingAgent(in: try fixtureValue(), with: entry)
    #expect(CursorRunMode.resolve(applicationUser: value) == .runEverything)
  }

  @Test func yoloEnableRunEverythingIsRunEverything() throws {
    let entry = agentEntry(
      autoRun: .bool(true), fullAutoRun: .bool(false), smartModeAutoRun: .bool(true))
    let value = replacingAgent(in: try fixtureValue(), with: entry, runEverything: true)
    #expect(CursorRunMode.resolve(applicationUser: value) == .runEverything)
  }

  @Test func neitherSmartNorFullIsAllowlist() throws {
    let entry = agentEntry(
      autoRun: .bool(true), fullAutoRun: .bool(false), smartModeAutoRun: .bool(false))
    let value = replacingAgent(in: try fixtureValue(), with: entry)
    #expect(CursorRunMode.resolve(applicationUser: value) == .allowlist)
  }

  @Test func nonObjectRootIsUnknown() {
    #expect(CursorRunMode.resolve(applicationUser: .array([])) == .unknown)
    #expect(CursorRunMode.resolve(applicationUser: .string("x")) == .unknown)
  }
}

@Suite struct CursorStateDatabaseTests {
  private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("cursor-state-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func createDatabase(at url: URL, key: String, value: Data) throws {
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let create = "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
    #expect(sqlite3_exec(database, create, nil, nil, nil) == SQLITE_OK)
    var statement: OpaquePointer?
    #expect(
      sqlite3_prepare_v2(
        database, "INSERT INTO ItemTable (key, value) VALUES (?1, ?2)", -1, &statement, nil)
        == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, 1, key, -1, transient)
    let text = String(decoding: value, as: UTF8.self)
    sqlite3_bind_text(statement, 2, text, -1, transient)
    #expect(sqlite3_step(statement) == SQLITE_DONE)
  }

  @Test func locatesTheDatabaseUnderApplicationSupport() {
    let home = URL(fileURLWithPath: "/Users/dev")
    #expect(
      CursorStateDatabase.location(home: home).path
        == "/Users/dev/Library/Application Support/Cursor/User/globalStorage/state.vscdb")
  }

  @Test func readsTheStoredTextByteForByte() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try FixtureLoader.data("cursor-state-application-user")
    let url = directory.appendingPathComponent("state.vscdb")
    try createDatabase(at: url, key: CursorStateDatabase.applicationUserKey, value: fixture)
    #expect(
      CursorStateDatabase.value(forKey: CursorStateDatabase.applicationUserKey, at: url)
        == fixture)
  }

  @Test func missingKeyIsNil() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.vscdb")
    try createDatabase(at: url, key: "other", value: Data("{}".utf8))
    #expect(CursorStateDatabase.value(forKey: "absent", at: url) == nil)
  }

  @Test func missingFileIsNil() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("absent.vscdb")
    #expect(CursorStateDatabase.value(forKey: "any", at: url) == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test func aFileThatIsNotSQLiteIsNil() throws {
    let directory = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("state.vscdb")
    try Data(repeating: 0x41, count: 4096).write(to: url)
    #expect(CursorStateDatabase.value(forKey: "any", at: url) == nil)
  }
}

@Suite struct CursorPermissionsFileTests {
  @Test func readsTheTerminalAllowlist() {
    let data = Data(#"{"terminalAllowlist": ["git status", "pnpm *"]}"#.utf8)
    #expect(CursorPermissionsFile.terminalAllowlist(in: data) == ["git status", "pnpm *"])
  }

  @Test func acceptsCommentsAndTrailingCommas() throws {
    let data = try FixtureLoader.data("cursor-permissions-jsonc")
    #expect(CursorPermissionsFile.terminalAllowlist(in: data) == ["git", "pnpm lint"])
  }

  @Test func absentKeyIsNil() {
    #expect(CursorPermissionsFile.terminalAllowlist(in: Data(#"{"other": []}"#.utf8)) == nil)
  }

  @Test func valueThatIsNotAnArrayIsNil() {
    let data = Data(#"{"terminalAllowlist": "git status"}"#.utf8)
    #expect(CursorPermissionsFile.terminalAllowlist(in: data) == nil)
  }

  @Test func oneNonStringElementIsNil() {
    let data = Data(#"{"terminalAllowlist": ["git status", 3]}"#.utf8)
    #expect(CursorPermissionsFile.terminalAllowlist(in: data) == nil)
  }

  @Test func rootThatIsNotAnObjectIsNil() {
    #expect(CursorPermissionsFile.terminalAllowlist(in: Data("[]".utf8)) == nil)
    #expect(CursorPermissionsFile.terminalAllowlist(in: Data("not json".utf8)) == nil)
  }

  @Test func missingFileIsNil() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("absent-\(UUID().uuidString)")
      .appendingPathComponent("permissions.json")
    #expect(CursorPermissionsFile.terminalAllowlist(at: url) == nil)
  }

  @Test func locatesTheUserAndWorkspaceFiles() {
    #expect(
      CursorPermissionsFile.userFile(home: URL(fileURLWithPath: "/Users/dev")).path
        == "/Users/dev/.cursor/permissions.json")
    #expect(
      CursorPermissionsFile.workspaceFile(root: URL(fileURLWithPath: "/work/shop")).path
        == "/work/shop/.cursor/permissions.json")
  }
}

@Suite struct CursorCommandAllowlistTests {
  @Test func inAppOnly() {
    let resolved = CursorCommandAllowlist.resolve(inApp: ["cd"], permissionsFiles: [nil, nil])
    #expect(resolved == CursorCommandAllowlist(patterns: ["cd"], source: .inApp))
  }

  @Test func userFileReplacesInApp() {
    let resolved = CursorCommandAllowlist.resolve(inApp: ["cd"], permissionsFiles: [["ls"], nil])
    #expect(resolved == CursorCommandAllowlist(patterns: ["ls"], source: .permissionsFiles))
  }

  @Test func userAndWorkspaceConcatenateInOrder() {
    let resolved = CursorCommandAllowlist.resolve(
      inApp: ["cd"], permissionsFiles: [["ls"], ["pwd", "git status"]])
    #expect(
      resolved
        == CursorCommandAllowlist(
          patterns: ["ls", "pwd", "git status"], source: .permissionsFiles))
  }

  @Test func workspaceOnlyReplacesInApp() {
    let resolved = CursorCommandAllowlist.resolve(inApp: ["cd"], permissionsFiles: [nil, ["pwd"]])
    #expect(resolved == CursorCommandAllowlist(patterns: ["pwd"], source: .permissionsFiles))
  }

  @Test func everythingNilIsNil() {
    #expect(CursorCommandAllowlist.resolve(inApp: nil, permissionsFiles: [nil, nil]) == nil)
    #expect(CursorCommandAllowlist.resolve(inApp: nil, permissionsFiles: []) == nil)
  }

  @Test func emptyInAppListIsDefined() {
    let resolved = CursorCommandAllowlist.resolve(inApp: [], permissionsFiles: [nil])
    #expect(resolved == CursorCommandAllowlist(patterns: [], source: .inApp))
  }

  @Test func emptyPermissionsFileIsDefined() {
    let resolved = CursorCommandAllowlist.resolve(inApp: ["cd"], permissionsFiles: [[], nil])
    #expect(resolved == CursorCommandAllowlist(patterns: [], source: .permissionsFiles))
  }
}

@Suite struct CursorEnvironmentTests {
  @Test func parsesTheFixture() throws {
    let data = try FixtureLoader.data("cursor-state-application-user")
    let environment = CursorEnvironment.parse(applicationUser: data, permissionsFiles: [nil, nil])
    #expect(environment.runMode == .autoReview)
    #expect(
      environment.commandAllowlist
        == CursorCommandAllowlist(patterns: ["cd", "pnpm lint"], source: .inApp))
  }

  @Test func missingDatabaseValueIsUnknown() {
    let environment = CursorEnvironment.parse(applicationUser: nil, permissionsFiles: [nil])
    #expect(environment.runMode == .unknown)
    #expect(environment.commandAllowlist == nil)
  }

  @Test func undecodableDatabaseValueIsUnknown() {
    let environment = CursorEnvironment.parse(
      applicationUser: Data("not json".utf8), permissionsFiles: [nil])
    #expect(environment.runMode == .unknown)
    #expect(environment.commandAllowlist == nil)
  }

  @Test func permissionsFilesStillApplyWithoutTheDatabase() {
    let environment = CursorEnvironment.parse(applicationUser: nil, permissionsFiles: [["ls"]])
    #expect(environment.runMode == .unknown)
    #expect(
      environment.commandAllowlist
        == CursorCommandAllowlist(patterns: ["ls"], source: .permissionsFiles))
  }

  @Test func readOfAnEmptyHomeIsUnknown() {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("no-cursor-\(UUID().uuidString)")
    let environment = CursorEnvironment.read(home: home, workspaceRoot: "")
    #expect(environment == CursorEnvironment(runMode: .unknown, commandAllowlist: nil))
  }

  @Test func logLineNamesTheSource() {
    let fromApp = CursorEnvironment(
      runMode: .autoReview,
      commandAllowlist: CursorCommandAllowlist(patterns: ["cd", "pnpm lint"], source: .inApp))
    #expect(fromApp.logLine == "cursor: run mode autoReview, allowlist 2 from the app")
    let fromFiles = CursorEnvironment(
      runMode: .allowlist,
      commandAllowlist: CursorCommandAllowlist(patterns: ["ls"], source: .permissionsFiles))
    #expect(fromFiles.logLine == "cursor: run mode allowlist, allowlist 1 from permissions.json")
    let unreadable = CursorEnvironment(runMode: .unknown, commandAllowlist: nil)
    #expect(unreadable.logLine == "cursor: run mode unknown, allowlist unreadable")
  }
}
