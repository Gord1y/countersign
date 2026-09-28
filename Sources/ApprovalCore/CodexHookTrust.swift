import Darwin
import Foundation

public enum CodexHookTrustState: Sendable, Equatable {
  case trusted
  case markedDone
  case pending(reason: String?, offersMarkAsDone: Bool)
  case unknown
}

public enum CodexHashAtWrite: Sendable, Equatable {
  case unread
  case absent
  case stored(String)

  public init(table: CodexTrustTable?, hookKey: String) {
    guard let table else {
      self = .unread
      return
    }
    self = table.trustedHashes[hookKey].map(CodexHashAtWrite.stored) ?? .absent
  }
}

public struct CodexHookTrustRecord: Sendable, Equatable {
  public let hookKey: String
  public let command: String
  public let hashAtWrite: CodexHashAtWrite
  public let learnedHash: String?
  public let markedDone: Bool

  public init(
    hookKey: String, command: String, hashAtWrite: CodexHashAtWrite = .unread,
    learnedHash: String? = nil, markedDone: Bool = false
  ) {
    self.hookKey = hookKey
    self.command = command
    self.hashAtWrite = hashAtWrite
    self.learnedHash = learnedHash
    self.markedDone = markedDone
  }

  public func learning(_ hash: String) -> CodexHookTrustRecord {
    CodexHookTrustRecord(
      hookKey: hookKey, command: command, hashAtWrite: hashAtWrite, learnedHash: hash,
      markedDone: markedDone)
  }
}

public struct CodexHookTrustCurrent: Sendable, Equatable {
  public let hookKey: String
  public let command: String
  public let hasMultipleEntries: Bool

  public init(hookKey: String, command: String, hasMultipleEntries: Bool) {
    self.hookKey = hookKey
    self.command = command
    self.hasMultipleEntries = hasMultipleEntries
  }
}

public enum CodexHookTrust {
  static let eventLabel = "permission_request"
  static let configFileName = "config.toml"

  public static func current(hooksFileBytes: [UInt8], hooksFilePath: String)
    -> CodexHookTrustCurrent?
  {
    guard let root = try? JSONSpanReader.parse(hooksFileBytes) else { return nil }
    let sites = HookSetup.sites(in: root)
    guard let first = sites.first else { return nil }
    let command = first.hook.member(named: "command")?.value.stringValue ?? ""
    let key = "\(hooksFilePath):\(eventLabel):\(first.groupIndex):\(first.hookIndex)"
    return CodexHookTrustCurrent(
      hookKey: key, command: command, hasMultipleEntries: sites.count > 1)
  }

  public static func configFile(for location: HookConfigLocation) -> URL {
    location.directory.appendingPathComponent(configFileName)
  }

  public static func writtenRecord(
    hooksFileBytes: [UInt8], hooksFilePath: String, config: Doctor.FileState
  ) -> CodexHookTrustRecord? {
    guard let current = current(hooksFileBytes: hooksFileBytes, hooksFilePath: hooksFilePath)
    else { return nil }
    let hashAtWrite: CodexHashAtWrite
    switch config {
    case .missing:
      hashAtWrite = .absent
    case .unreadable:
      hashAtWrite = .unread
    case .bytes(let bytes):
      hashAtWrite = CodexHashAtWrite(
        table: CodexTrustTable(configBytes: bytes), hookKey: current.hookKey)
    }
    return CodexHookTrustRecord(
      hookKey: current.hookKey, command: current.command, hashAtWrite: hashAtWrite)
  }

  public static func markedRecord(
    existing: CodexHookTrustRecord?, current: CodexHookTrustCurrent, table: CodexTrustTable?
  ) -> CodexHookTrustRecord {
    let kept = existing.flatMap { $0.command == current.command ? $0 : nil }
    let hashAtWrite: CodexHashAtWrite
    if let kept, kept.hookKey == current.hookKey {
      hashAtWrite = kept.hashAtWrite
    } else {
      hashAtWrite = CodexHashAtWrite(table: table, hookKey: current.hookKey)
    }
    return CodexHookTrustRecord(
      hookKey: current.hookKey, command: current.command, hashAtWrite: hashAtWrite,
      learnedHash: kept?.learnedHash, markedDone: true)
  }

  public static func check(
    _ location: HookConfigLocation, recordFile: URL, persistsLearnedHash: Bool
  ) -> CodexHookTrustState {
    let record = CodexHookTrustRecordStore.load(file: recordFile)
    let verdict = CodexTrustVerdict.judge(
      record: record, current: currentEntry(at: location),
      table: CodexTrustTable.read(ConfigFileStore.fileState(configFile(for: location))))
    if persistsLearnedHash, let record, let learned = verdict.newlyLearnedHash {
      try? CodexHookTrustRecordStore.save(record.learning(learned), to: recordFile)
    }
    return verdict.state
  }

  public static func markAsDone(_ location: HookConfigLocation, recordFile: URL) throws {
    guard let current = currentEntry(at: location) else { return }
    let record = markedRecord(
      existing: CodexHookTrustRecordStore.load(file: recordFile), current: current,
      table: CodexTrustTable.read(ConfigFileStore.fileState(configFile(for: location))))
    try CodexHookTrustRecordStore.save(record, to: recordFile)
  }

  private static func currentEntry(at location: HookConfigLocation) -> CodexHookTrustCurrent? {
    guard case .bytes(let bytes) = ConfigFileStore.fileState(location.file) else { return nil }
    return current(hooksFileBytes: bytes, hooksFilePath: location.file.path)
  }
}

public enum CodexHookTrustRecordStore {
  public static func load(file: URL) -> CodexHookTrustRecord? {
    guard let data = try? Data(contentsOf: file) else { return nil }
    return decode(data)
  }

  public static func save(_ record: CodexHookTrustRecord, to file: URL) throws {
    let directory = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(
      ".\(file.lastPathComponent).countersign-\(UUID().uuidString).tmp")
    try encode(record).write(to: temporary)
    guard rename(temporary.path, file.path) == 0 else {
      let code = errno
      unlink(temporary.path)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  public static func delete(file: URL) {
    try? FileManager.default.removeItem(at: file)
  }

  static func encode(_ record: CodexHookTrustRecord) -> Data {
    var members: [String: JSONValue] = [
      "hookKey": .string(record.hookKey),
      "command": .string(record.command),
      "markedDone": .bool(record.markedDone),
      "hashAtWriteKnown": .bool(record.hashAtWrite != .unread),
    ]
    if case .stored(let hash) = record.hashAtWrite {
      members["hashAtWrite"] = .string(hash)
    }
    members["learnedHash"] = record.learnedHash.map(JSONValue.string)
    return (try? JSONEncoder().encode(JSONValue.object(members))) ?? Data()
  }

  static func decode(_ data: Data) -> CodexHookTrustRecord? {
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
      case .object(let root) = value,
      case .string(let hookKey)? = root["hookKey"],
      case .string(let command)? = root["command"],
      let storedHash = optionalString(root["hashAtWrite"]),
      let hashAtWriteKnown = optionalBool(root["hashAtWriteKnown"]),
      let learnedHash = optionalString(root["learnedHash"]),
      let markedDone = optionalBool(root["markedDone"])
    else { return nil }
    let hashAtWrite: CodexHashAtWrite =
      hashAtWriteKnown ? storedHash.map(CodexHashAtWrite.stored) ?? .absent : .unread
    return CodexHookTrustRecord(
      hookKey: hookKey, command: command, hashAtWrite: hashAtWrite, learnedHash: learnedHash,
      markedDone: markedDone)
  }

  private static func optionalString(_ value: JSONValue?) -> String?? {
    switch value {
    case nil, .null?:
      return .some(nil)
    case .string(let text)?:
      return .some(text)
    default:
      return nil
    }
  }

  private static func optionalBool(_ value: JSONValue?) -> Bool? {
    switch value {
    case nil, .null?:
      return false
    case .bool(let flag)?:
      return flag
    default:
      return nil
    }
  }
}
