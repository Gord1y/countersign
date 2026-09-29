import Darwin
import Foundation

public struct TicketSummary: Codable, Sendable, Equatable {
  public var host: Host
  public var project: String
  public var tool: String
  public var agentType: String?
  public var agentDescription: String?
  public var isTestPanel: Bool
  public var isContextCheckpoint: Bool

  public init(
    host: Host, project: String, tool: String, agentType: String?,
    agentDescription: String? = nil, isTestPanel: Bool = false, isContextCheckpoint: Bool = false
  ) {
    self.host = host
    self.project = project
    self.tool = tool
    self.agentType = agentType
    self.agentDescription = agentDescription
    self.isTestPanel = isTestPanel
    self.isContextCheckpoint = isContextCheckpoint
  }

  public init(request: ApprovalRequest, agentDescription: String? = nil, isTestPanel: Bool = false)
  {
    self.init(
      host: request.host,
      project: request.projectName,
      tool: request.toolName,
      agentType: request.agentType,
      agentDescription: agentDescription,
      isTestPanel: isTestPanel,
      isContextCheckpoint: Self.isContextCheckpoint(request.kind)
    )
  }

  private static func isContextCheckpoint(_ kind: RequestKind) -> Bool {
    guard case .contextCheckpoint = kind else { return false }
    return true
  }

  public var agentLabel: String? {
    guard let agentType else { return nil }
    if let agentDescription, !agentDescription.isEmpty {
      return agentDescription
    }
    return agentType
  }

  private enum CodingKeys: String, CodingKey {
    case host, project, tool, agentType, agentDescription, isTestPanel, isContextCheckpoint
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    host = try container.decode(Host.self, forKey: .host)
    project = try container.decode(String.self, forKey: .project)
    tool = try container.decode(String.self, forKey: .tool)
    agentType = try container.decodeIfPresent(String.self, forKey: .agentType)
    agentDescription = try container.decodeIfPresent(String.self, forKey: .agentDescription)
    isTestPanel = try container.decodeIfPresent(Bool.self, forKey: .isTestPanel) ?? false
    isContextCheckpoint =
      try container.decodeIfPresent(Bool.self, forKey: .isContextCheckpoint) ?? false
  }
}

public struct WaitingEntry: Sendable, Equatable {
  public var summary: TicketSummary?

  public init(summary: TicketSummary?) {
    self.summary = summary
  }
}

public struct Ticket: Sendable, Equatable {
  public let fileName: String
  public let timestamp: UInt64
  public let pid: Int32
  public let processStart: UInt64?
  public let summary: TicketSummary?

  static let timestampDigits = 20
  static let fileSuffix = ".json"

  static func fileName(timestamp: UInt64, pid: Int32) -> String {
    let digits = String(timestamp)
    let padding = String(repeating: "0", count: max(0, timestampDigits - digits.count))
    return "\(padding)\(digits)-\(pid)\(fileSuffix)"
  }

  static func parseFileName(_ fileName: String) -> (timestamp: UInt64, pid: Int32)? {
    guard !fileName.hasPrefix("."), fileName.hasSuffix(fileSuffix) else { return nil }
    let stem = fileName.dropLast(fileSuffix.count)
    let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].count == timestampDigits,
      isASCIIDigits(parts[0]), isASCIIDigits(parts[1]),
      let timestamp = UInt64(parts[0]), let pid = Int32(parts[1]), pid > 0
    else { return nil }
    return (timestamp, pid)
  }

  private static func isASCIIDigits(_ text: Substring) -> Bool {
    !text.isEmpty && text.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
  }
}

struct TicketContent: Codable, Equatable {
  var processStart: UInt64?
  var summary: TicketSummary?
}

public struct TicketQueue: Sendable {
  let directory: URL
  let lockFile: URL

  public init(directory: URL, lockFile: URL) {
    self.directory = directory
    self.lockFile = lockFile
  }

  public func enqueue(_ summary: TicketSummary) throws -> Ticket {
    let pid = getpid()
    let timestamp = clock_gettime_nsec_np(CLOCK_REALTIME)
    let ticket = Ticket(
      fileName: Ticket.fileName(timestamp: timestamp, pid: pid),
      timestamp: timestamp,
      pid: pid,
      processStart: ProcessLiveness.startTime(of: pid),
      summary: summary
    )
    try write(ticket)
    return ticket
  }

  public func remove(_ ticket: Ticket) {
    unlink(url(for: ticket).path)
  }

  public func liveTickets() -> [Ticket] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    var live: [Ticket] = []
    for name in names where name != lockFile.lastPathComponent {
      guard let ticket = readTicket(named: name) else { continue }
      if ProcessLiveness.isAlive(pid: ticket.pid, processStart: ticket.processStart) {
        live.append(ticket)
      } else {
        unlink(url(for: ticket).path)
      }
    }
    return live.sorted { ($0.timestamp, $0.pid) < ($1.timestamp, $1.pid) }
  }

  public func isHead(_ ticket: Ticket) -> Bool {
    liveTickets().first?.fileName == ticket.fileName
  }

  public func waitingCount(excluding ticket: Ticket) -> Int {
    liveTickets().filter { $0.fileName != ticket.fileName }.count
  }

  public func realRequestCount(excluding ticket: Ticket) -> Int {
    liveTickets().filter { $0.fileName != ticket.fileName && $0.summary?.isTestPanel != true }
      .count
  }

  public func approvalCount(excluding ticket: Ticket?) -> Int {
    liveTickets().filter {
      $0.fileName != ticket?.fileName && $0.summary?.isTestPanel != true
        && $0.summary?.isContextCheckpoint != true
    }.count
  }

  public func waitingEntries(excluding ticket: Ticket) -> [WaitingEntry] {
    liveTickets().filter { $0.fileName != ticket.fileName }.map {
      WaitingEntry(summary: $0.summary)
    }
  }

  public func waitingEntries() -> [WaitingEntry] {
    liveTickets().map { WaitingEntry(summary: $0.summary) }
  }

  public func acquireDisplayIfHead(_ ticket: Ticket) -> DisplayLease? {
    restoreIfVanished(ticket)
    guard isHead(ticket) else { return nil }
    return DisplayLease.acquire(lockFile: lockFile)
  }

  public func waitForDisplay(
    _ ticket: Ticket,
    pollInterval: Duration,
    shouldAbandon: () -> Bool
  ) -> DisplayLease? {
    while !shouldAbandon() {
      if let lease = acquireDisplayIfHead(ticket) {
        return lease
      }
      Thread.sleep(forTimeInterval: Self.seconds(pollInterval))
    }
    return nil
  }

  public func removeOnTermination(_ ticket: Ticket) {
    TerminationCleanup.shared.register(url(for: ticket))
  }

  func url(for ticket: Ticket) -> URL {
    directory.appendingPathComponent(ticket.fileName)
  }

  private func readTicket(named name: String) -> Ticket? {
    guard let parsed = Ticket.parseFileName(name) else { return nil }
    let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path)
    let content = data.flatMap { try? JSONDecoder().decode(TicketContent.self, from: $0) }
    return Ticket(
      fileName: name,
      timestamp: parsed.timestamp,
      pid: parsed.pid,
      processStart: content?.processStart,
      summary: content?.summary
    )
  }

  private func restoreIfVanished(_ ticket: Ticket) {
    guard ticket.pid == getpid(), !FileManager.default.fileExists(atPath: url(for: ticket).path)
    else { return }
    try? write(ticket)
  }

  private func write(_ ticket: Ticket) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let content = TicketContent(processStart: ticket.processStart, summary: ticket.summary)
    let data = try encoder.encode(content)
    let temporary = directory.appendingPathComponent(".\(ticket.fileName).tmp")
    try data.write(to: temporary)
    guard rename(temporary.path, url(for: ticket).path) == 0 else {
      let code = errno
      unlink(temporary.path)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  private static func seconds(_ duration: Duration) -> TimeInterval {
    let components = duration.components
    return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
  }
}

public final class DisplayLease: Sendable {
  private let lock: ExclusiveFileLock

  private init(lock: ExclusiveFileLock) {
    self.lock = lock
  }

  static func acquire(lockFile: URL) -> DisplayLease? {
    guard let lock = try? ExclusiveFileLock.acquire(lockFile) else { return nil }
    return DisplayLease(lock: lock)
  }

  public func release() {
    lock.release()
  }
}
