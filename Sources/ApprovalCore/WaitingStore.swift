import Darwin
import Foundation

public enum WaitingReason: String, Sendable, Codable, Equatable {
  case turnEnded
  case handedBack
}

public struct WaitingRecord: Sendable, Codable, Equatable {
  public var host: Host
  public var sessionID: String
  public var projectName: String
  public var projectPath: String
  public var transcriptPath: String?
  public var reason: WaitingReason
  public var recordedAt: Date
  public var appBundleID: String?
  public var appPID: Int32?
  public var appName: String?
  public var agentPID: Int32?
  public var agentStart: UInt64?

  public init(
    host: Host, sessionID: String, projectName: String, projectPath: String,
    transcriptPath: String?, reason: WaitingReason, recordedAt: Date,
    appBundleID: String? = nil, appPID: Int32? = nil, appName: String? = nil,
    agentPID: Int32? = nil, agentStart: UInt64? = nil
  ) {
    self.host = host
    self.sessionID = sessionID
    self.projectName = projectName
    self.projectPath = projectPath
    self.transcriptPath = transcriptPath
    self.reason = reason
    self.recordedAt = recordedAt
    self.appBundleID = appBundleID
    self.appPID = appPID
    self.appName = appName
    self.agentPID = agentPID
    self.agentStart = agentStart
  }
}

public struct ApprovalClaim: Sendable, Codable, Equatable {
  public var pid: Int32
  public var processStart: UInt64?

  public init(pid: Int32, processStart: UInt64?) {
    self.pid = pid
    self.processStart = processStart
  }

  public static func current() -> ApprovalClaim {
    let pid = getpid()
    return ApprovalClaim(pid: pid, processStart: ProcessLiveness.startTime(of: pid))
  }

  public var isLive: Bool {
    ProcessLiveness.isAlive(pid: pid, processStart: processStart)
  }
}

public struct WaitingStore: Sendable {
  public static let maximumKeyLength = 80
  public static let slotCount = 2

  public let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public static func key(for sessionID: String) -> String {
    let sanitized = sessionID.map { character -> Character in
      isAllowed(character) ? character : "_"
    }
    return String(sanitized.prefix(maximumKeyLength))
  }

  public func recordFile(host: Host, sessionID: String) -> URL {
    directory.appendingPathComponent("\(Self.baseName(host: host, sessionID: sessionID)).json")
  }

  public func recordFile(for record: WaitingRecord) -> URL {
    recordFile(host: record.host, sessionID: record.sessionID)
  }

  public func lockFile(for record: WaitingRecord) -> URL {
    directory.appendingPathComponent(
      "\(Self.baseName(host: record.host, sessionID: record.sessionID)).lock")
  }

  public func slotLockFile(_ slot: Int) -> URL {
    directory.appendingPathComponent("slot-\(slot).lock")
  }

  public var approvalClaimFile: URL {
    directory.appendingPathComponent("approval-claim.json")
  }

  @discardableResult
  public func save(_ record: WaitingRecord) throws -> URL {
    let file = recordFile(for: record)
    try writeAtomically(record, to: file)
    return file
  }

  public func writeApprovalClaim(_ claim: ApprovalClaim) throws {
    try writeAtomically(claim, to: approvalClaimFile)
  }

  public func liveApprovalClaim() -> ApprovalClaim? {
    guard let claim = storedApprovalClaim(), claim.isLive else { return nil }
    return claim
  }

  public func removeApprovalClaim(_ claim: ApprovalClaim) {
    guard storedApprovalClaim() == claim else { return }
    unlink(approvalClaimFile.path)
  }

  public func load(_ file: URL) -> WaitingRecord? {
    guard let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(WaitingRecord.self, from: data)
  }

  public func delete(_ file: URL) {
    unlink(file.path)
  }

  @discardableResult
  public func deleteRecord(host: Host, sessionID: String) -> Bool {
    unlink(recordFile(host: host, sessionID: sessionID).path) == 0
  }

  private func storedApprovalClaim() -> ApprovalClaim? {
    guard let data = try? Data(contentsOf: approvalClaimFile) else { return nil }
    return try? JSONDecoder().decode(ApprovalClaim.self, from: data)
  }

  private func writeAtomically(_ value: some Encodable, to file: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(
      ".\(file.lastPathComponent).countersign-\(UUID().uuidString).tmp")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(value).write(to: temporary)
    guard rename(temporary.path, file.path) == 0 else {
      let code = errno
      unlink(temporary.path)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  private static func baseName(host: Host, sessionID: String) -> String {
    "\(host.rawValue)-\(key(for: sessionID))"
  }

  private static func isAllowed(_ character: Character) -> Bool {
    guard character.isASCII else { return false }
    return character.isLetter || character.isNumber || character == "." || character == "_"
      || character == "-"
  }
}
