import Foundation
import Testing

@testable import ApprovalCore

private let hooksPath = "/Users/dev/.codex/hooks.json"
private let brewPath = "/opt/homebrew/bin/countersign"

private func codexHooksJSON(groups: [[String]]) -> [UInt8] {
  let groupsText = groups.map { commands in
    let hooksText = commands.map { command in
      """
      { "type": "command", "command": "\(command)", "timeout": 3600 }
      """
    }.joined(separator: ", ")
    return """
      { "matcher": "", "hooks": [\(hooksText)] }
      """
  }.joined(separator: ", ")
  return Array(
    """
    { "hooks": { "PermissionRequest": [\(groupsText)] } }
    """.utf8)
}

@Suite struct CodexHookTrustTests {
  @Test func currentReadsTheFirstEntrysKeyAndCommand() {
    let bytes = codexHooksJSON(groups: [["\(brewPath) hook --host codex"]])
    let current = CodexHookTrust.current(hooksFileBytes: bytes, hooksFilePath: hooksPath)
    #expect(current?.hookKey == "\(hooksPath):permission_request:0:0")
    #expect(current?.command == "\(brewPath) hook --host codex")
    #expect(current?.hasMultipleEntries == false)
  }

  @Test func currentUsesTheSecondGroupsIndexWhenTheFirstHasNoEntryOfOurs() {
    let bytes = Array(
      """
      { "hooks": { "PermissionRequest": [
        { "matcher": "", "hooks": [{ "type": "command", "command": "~/audit.sh" }] },
        { "matcher": "", "hooks": [{ "type": "command", "command": "\(brewPath) hook --host codex", "timeout": 3600 }] }
      ] } }
      """.utf8)
    let current = CodexHookTrust.current(hooksFileBytes: bytes, hooksFilePath: hooksPath)
    #expect(current?.hookKey == "\(hooksPath):permission_request:1:0")
  }

  @Test func currentFlagsMultipleEntriesAndUsesTheFirst() {
    let bytes = codexHooksJSON(groups: [
      ["\(brewPath) hook --host codex", "\(brewPath) hook --host codex --verbose"]
    ])
    let current = CodexHookTrust.current(hooksFileBytes: bytes, hooksFilePath: hooksPath)
    #expect(current?.hookKey == "\(hooksPath):permission_request:0:0")
    #expect(current?.command == "\(brewPath) hook --host codex")
    #expect(current?.hasMultipleEntries == true)
  }

  @Test func currentIsNilWhenTheFileIsNotValidJSON() {
    #expect(
      CodexHookTrust.current(hooksFileBytes: Array("{not json".utf8), hooksFilePath: hooksPath)
        == nil)
  }

  @Test func currentIsNilWithNoEntryOfOurs() {
    let bytes = Array("{}".utf8)
    #expect(CodexHookTrust.current(hooksFileBytes: bytes, hooksFilePath: hooksPath) == nil)
  }

  @Test func learningKeepsEverythingElseInTheRecord() {
    let record = CodexHookTrustRecord(
      hookKey: "k", command: "c", hashAtWrite: .stored("sha256:a"), markedDone: true)
    #expect(
      record.learning("sha256:b")
        == CodexHookTrustRecord(
          hookKey: "k", command: "c", hashAtWrite: .stored("sha256:a"), learnedHash: "sha256:b",
          markedDone: true))
  }

  @Test func aRecordKnowsNothingAboutTheHashAtWriteUnlessToldSo() {
    #expect(CodexHookTrustRecord(hookKey: "k", command: "c").hashAtWrite == .unread)
  }

  @Test func tellsAnUnreadConfigFromAnAbsentHash() {
    let table = CodexTrustTable(trustedHashes: ["k": "sha256:a"])
    #expect(CodexHashAtWrite(table: nil, hookKey: "k") == .unread)
    #expect(CodexHashAtWrite(table: table, hookKey: "other") == .absent)
    #expect(CodexHashAtWrite(table: table, hookKey: "k") == .stored("sha256:a"))
  }

  @Test func keepsCodexsConfigNextToItsHooksFile() {
    let location = HookConfigLocation.location(
      for: .codex, environment: ["CODEX_HOME": "/tmp/codex-home"], home: URL(fileURLWithPath: "/"))
    #expect(CodexHookTrust.configFile(for: location).path == "/tmp/codex-home/config.toml")
  }

  @Test func writtenRecordTakesTheHashStoredAtOurKeyAtWriteTime() {
    let bytes = codexHooksJSON(groups: [["~/audit.sh"], ["\(brewPath) hook --host codex"]])
    let key = "\(hooksPath):permission_request:1:0"
    let config = Array("[hooks.state.\"\(key)\"]\ntrusted_hash = \"sha256:old\"\n".utf8)
    #expect(
      CodexHookTrust.writtenRecord(
        hooksFileBytes: bytes, hooksFilePath: hooksPath, config: .bytes(config))
        == CodexHookTrustRecord(
          hookKey: key, command: "\(brewPath) hook --host codex",
          hashAtWrite: .stored("sha256:old")))
    #expect(
      CodexHookTrust.writtenRecord(
        hooksFileBytes: bytes, hooksFilePath: hooksPath, config: .bytes(Array("x = 1\n".utf8)))
        == CodexHookTrustRecord(
          hookKey: key, command: "\(brewPath) hook --host codex", hashAtWrite: .absent))
    #expect(
      CodexHookTrust.writtenRecord(
        hooksFileBytes: bytes, hooksFilePath: hooksPath, config: .missing)
        == CodexHookTrustRecord(
          hookKey: key, command: "\(brewPath) hook --host codex", hashAtWrite: .absent))
  }

  @Test func writtenRecordSaysSoWhenItCouldNotReadTheConfig() {
    let bytes = codexHooksJSON(groups: [["\(brewPath) hook --host codex"]])
    let unread = CodexHookTrustRecord(
      hookKey: "\(hooksPath):permission_request:0:0", command: "\(brewPath) hook --host codex",
      hashAtWrite: .unread)
    #expect(
      CodexHookTrust.writtenRecord(
        hooksFileBytes: bytes, hooksFilePath: hooksPath, config: .unreadable("denied")) == unread)
    #expect(
      CodexHookTrust.writtenRecord(
        hooksFileBytes: bytes, hooksFilePath: hooksPath, config: .bytes([0xFF])) == unread)
    #expect(
      CodexHookTrust.writtenRecord(
        hooksFileBytes: bytes, hooksFilePath: hooksPath,
        config: .bytes(Array("[hooks]\nstate = {}\n".utf8))) == unread)
  }

  @Test func writtenRecordIsNilWithoutOurEntry() {
    #expect(
      CodexHookTrust.writtenRecord(
        hooksFileBytes: Array("{}".utf8), hooksFilePath: hooksPath, config: .missing) == nil)
  }

  @Test func markedRecordKeepsWhatStillBelongsToTheEntry() {
    let current = CodexHookTrustCurrent(hookKey: "k1", command: "c", hasMultipleEntries: false)
    let table = CodexTrustTable(trustedHashes: ["k1": "sha256:now"])
    let sameEntry = CodexHookTrustRecord(
      hookKey: "k1", command: "c", hashAtWrite: .stored("sha256:write"),
      learnedHash: "sha256:learned")
    #expect(
      CodexHookTrust.markedRecord(existing: sameEntry, current: current, table: nil)
        == CodexHookTrustRecord(
          hookKey: "k1", command: "c", hashAtWrite: .stored("sha256:write"),
          learnedHash: "sha256:learned", markedDone: true))
    let moved = CodexHookTrustRecord(
      hookKey: "k0", command: "c", hashAtWrite: .stored("sha256:write"),
      learnedHash: "sha256:learned")
    #expect(
      CodexHookTrust.markedRecord(existing: moved, current: current, table: table)
        == CodexHookTrustRecord(
          hookKey: "k1", command: "c", hashAtWrite: .stored("sha256:now"),
          learnedHash: "sha256:learned", markedDone: true))
    let otherCommand = CodexHookTrustRecord(
      hookKey: "k1", command: "old", hashAtWrite: .stored("sha256:write"),
      learnedHash: "sha256:learned")
    #expect(
      CodexHookTrust.markedRecord(
        existing: otherCommand, current: current, table: CodexTrustTable(trustedHashes: [:]))
        == CodexHookTrustRecord(hookKey: "k1", command: "c", hashAtWrite: .absent, markedDone: true)
    )
    #expect(
      CodexHookTrust.markedRecord(existing: nil, current: current, table: table)
        == CodexHookTrustRecord(
          hookKey: "k1", command: "c", hashAtWrite: .stored("sha256:now"), markedDone: true))
  }

  @Test func markedRecordSaysSoWhenItCouldNotReadTheConfig() {
    let current = CodexHookTrustCurrent(hookKey: "k1", command: "c", hasMultipleEntries: false)
    let moved = CodexHookTrustRecord(hookKey: "k0", command: "c", hashAtWrite: .absent)
    #expect(
      CodexHookTrust.markedRecord(existing: moved, current: current, table: nil)
        == CodexHookTrustRecord(hookKey: "k1", command: "c", hashAtWrite: .unread, markedDone: true)
    )
    #expect(
      CodexHookTrust.markedRecord(existing: nil, current: current, table: nil)
        == CodexHookTrustRecord(hookKey: "k1", command: "c", hashAtWrite: .unread, markedDone: true)
    )
  }
}

@Suite struct CodexHookTrustCheckTests {
  private struct Home {
    let root: URL
    let location: HookConfigLocation
    let recordFile: URL

    init() throws {
      root = FileManager.default.temporaryDirectory
        .appendingPathComponent("countersign-codex-trust-check-\(UUID().uuidString)")
      location = HookConfigLocation.location(for: .codex, environment: [:], home: root)
      recordFile = AppPaths(home: root).codexHookTrustFile
      try FileManager.default.createDirectory(
        at: location.directory, withIntermediateDirectories: true)
    }

    var key: String {
      "\(location.file.path):permission_request:0:0"
    }

    func put(hooks: [UInt8]) throws {
      try Data(hooks).write(to: location.file)
    }

    func put(trustedHash: String) throws {
      try Data("[hooks.state.\"\(key)\"]\ntrusted_hash = \"\(trustedHash)\"\n".utf8).write(
        to: CodexHookTrust.configFile(for: location))
    }

    func remove() {
      try? FileManager.default.removeItem(at: root)
    }
  }

  private let command = "\(brewPath) hook --host codex"

  @Test func checksAndPersistsANewlyLearnedHash() throws {
    let home = try Home()
    defer { home.remove() }
    try home.put(hooks: codexHooksJSON(groups: [[command]]))
    try home.put(trustedHash: "sha256:ours")
    try CodexHookTrustRecordStore.save(
      CodexHookTrustRecord(hookKey: home.key, command: command, hashAtWrite: .absent),
      to: home.recordFile)

    #expect(
      CodexHookTrust.check(home.location, recordFile: home.recordFile, persistsLearnedHash: false)
        == .trusted)
    #expect(CodexHookTrustRecordStore.load(file: home.recordFile)?.learnedHash == nil)
    #expect(
      CodexHookTrust.check(home.location, recordFile: home.recordFile, persistsLearnedHash: true)
        == .trusted)
    #expect(CodexHookTrustRecordStore.load(file: home.recordFile)?.learnedHash == "sha256:ours")
  }

  @Test func neverLearnsFromARecordWrittenWithoutReadingTheConfig() throws {
    let home = try Home()
    defer { home.remove() }
    try home.put(hooks: codexHooksJSON(groups: [[command]]))
    try home.put(trustedHash: "sha256:appeared")
    let written = CodexHookTrustRecord(hookKey: home.key, command: command, hashAtWrite: .unread)
    try CodexHookTrustRecordStore.save(written, to: home.recordFile)

    #expect(
      CodexHookTrust.check(home.location, recordFile: home.recordFile, persistsLearnedHash: true)
        == .pending(reason: nil, offersMarkAsDone: true))
    #expect(CodexHookTrustRecordStore.load(file: home.recordFile) == written)
  }

  @Test func checkIsUnknownWithoutOurEntry() throws {
    let home = try Home()
    defer { home.remove() }
    #expect(
      CodexHookTrust.check(home.location, recordFile: home.recordFile, persistsLearnedHash: true)
        == .unknown)
    #expect(CodexHookTrustRecordStore.load(file: home.recordFile) == nil)
  }

  @Test func marksTheCurrentEntryAsDone() throws {
    let home = try Home()
    defer { home.remove() }
    try home.put(hooks: codexHooksJSON(groups: [[command]]))
    try home.put(trustedHash: "sha256:now")

    try CodexHookTrust.markAsDone(home.location, recordFile: home.recordFile)

    #expect(
      CodexHookTrustRecordStore.load(file: home.recordFile)
        == CodexHookTrustRecord(
          hookKey: home.key, command: command, hashAtWrite: .stored("sha256:now"),
          markedDone: true))
    #expect(
      CodexHookTrust.check(home.location, recordFile: home.recordFile, persistsLearnedHash: true)
        == .markedDone)
  }

  @Test func markingWithoutOurEntryWritesNothing() throws {
    let home = try Home()
    defer { home.remove() }
    try home.put(hooks: Array("{}".utf8))
    try CodexHookTrust.markAsDone(home.location, recordFile: home.recordFile)
    #expect(CodexHookTrustRecordStore.load(file: home.recordFile) == nil)
  }
}

@Suite struct CodexHookTrustRecordStoreTests {
  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-codex-hook-trust-\(UUID().uuidString)")
      .appendingPathComponent("nested")
      .appendingPathComponent("codex-hook-trust.json")
  }

  private func removeContainer(of file: URL) {
    let container = file.deletingLastPathComponent().deletingLastPathComponent()
    try? FileManager.default.removeItem(at: container)
  }

  @Test func loadReturnsNilWhenTheFileIsMissing() {
    #expect(CodexHookTrustRecordStore.load(file: temporaryFile()) == nil)
  }

  @Test func savesAndLoadsARecord() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let record = CodexHookTrustRecord(
      hookKey: "\(hooksPath):permission_request:0:0", command: brewPath)

    try CodexHookTrustRecordStore.save(record, to: file)

    #expect(CodexHookTrustRecordStore.load(file: file) == record)
  }

  @Test func saveOverwritesAPreviousRecord() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try CodexHookTrustRecordStore.save(CodexHookTrustRecord(hookKey: "a", command: "b"), to: file)
    let second = CodexHookTrustRecord(hookKey: "c", command: "d")

    try CodexHookTrustRecordStore.save(second, to: file)

    #expect(CodexHookTrustRecordStore.load(file: file) == second)
  }

  @Test func deleteRemovesTheFile() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try CodexHookTrustRecordStore.save(CodexHookTrustRecord(hookKey: "a", command: "b"), to: file)

    CodexHookTrustRecordStore.delete(file: file)

    #expect(CodexHookTrustRecordStore.load(file: file) == nil)
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func deleteDoesNothingWhenTheFileIsMissing() {
    CodexHookTrustRecordStore.delete(file: temporaryFile())
  }

  @Test func loadReturnsNilForCorruptedJSON() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: file)

    #expect(CodexHookTrustRecordStore.load(file: file) == nil)
  }

  @Test func loadReturnsNilWhenHookKeyIsMissing() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"command": "c"}"#.utf8).write(to: file)

    #expect(CodexHookTrustRecordStore.load(file: file) == nil)
  }

  @Test func loadReturnsNilWhenCommandIsMissing() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"hookKey": "k"}"#.utf8).write(to: file)

    #expect(CodexHookTrustRecordStore.load(file: file) == nil)
  }

  @Test func saveFailsCleanlyWhenTheRecordPathIsADirectory() throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    try FileManager.default.createDirectory(
      at: file.appendingPathComponent("inside"), withIntermediateDirectories: true)

    #expect(throws: (any Error).self) {
      try CodexHookTrustRecordStore.save(
        CodexHookTrustRecord(hookKey: "a", command: "b"), to: file)
    }
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        == [file.lastPathComponent])
  }

  @Test(arguments: [CodexHashAtWrite.stored("sha256:a"), .absent, .unread])
  func savesAndLoadsEveryFieldOfARecord(hashAtWrite: CodexHashAtWrite) throws {
    let file = temporaryFile()
    defer { removeContainer(of: file) }
    let record = CodexHookTrustRecord(
      hookKey: "k", command: "c", hashAtWrite: hashAtWrite, learnedHash: "sha256:b",
      markedDone: true)

    try CodexHookTrustRecordStore.save(record, to: file)

    #expect(CodexHookTrustRecordStore.load(file: file) == record)
  }

  @Test(arguments: [
    (
      #"{"hookKey": "k", "command": "c"}"#,
      CodexHookTrustRecord(hookKey: "k", command: "c", hashAtWrite: .unread)
    ),
    (
      #"{"hookKey": "k", "command": "c", "hashAtWrite": null, "hashAtWriteKnown": null, "learnedHash": null, "markedDone": null}"#,
      CodexHookTrustRecord(hookKey: "k", command: "c", hashAtWrite: .unread)
    ),
    (
      #"{"hookKey": "k", "command": "c", "hashAtWrite": "a", "markedDone": false}"#,
      CodexHookTrustRecord(hookKey: "k", command: "c", hashAtWrite: .unread)
    ),
    (
      #"{"hookKey": "k", "command": "c", "hashAtWriteKnown": false, "hashAtWrite": "a"}"#,
      CodexHookTrustRecord(hookKey: "k", command: "c", hashAtWrite: .unread)
    ),
    (
      #"{"hookKey": "k", "command": "c", "hashAtWriteKnown": true}"#,
      CodexHookTrustRecord(hookKey: "k", command: "c", hashAtWrite: .absent)
    ),
    (
      #"{"hookKey": "k", "command": "c", "hashAtWriteKnown": true, "hashAtWrite": "a"}"#,
      CodexHookTrustRecord(hookKey: "k", command: "c", hashAtWrite: .stored("a"))
    ),
  ])
  func decodesMissingFieldsAsNothingKnown(json: String, record: CodexHookTrustRecord) {
    #expect(CodexHookTrustRecordStore.decode(Data(json.utf8)) == record)
  }

  @Test(arguments: [
    #"{"hookKey": "k", "command": "c", "hashAtWrite": 1}"#,
    #"{"hookKey": "k", "command": "c", "hashAtWriteKnown": "yes"}"#,
    #"{"hookKey": "k", "command": "c", "learnedHash": true}"#,
    #"{"hookKey": "k", "command": "c", "markedDone": "yes"}"#,
  ])
  func refusesAFieldOfTheWrongType(json: String) {
    #expect(CodexHookTrustRecordStore.decode(Data(json.utf8)) == nil)
  }
}
