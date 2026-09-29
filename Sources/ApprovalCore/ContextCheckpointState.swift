import Darwin
import Foundation

public struct ContextCheckpointState: Sendable, Codable, Equatable {
  public var fired: [ContextLevel]
  public var peakTokens: Int
  public var lastTokens: Int
  public var compactionID: String?
  public var modelID: String?
  public var muted: Bool
  public var transcriptPath: String?
  public var project: String?
  public var pendingProcessID: Int32?
  public var updatedAt: Date

  public static func fresh(now: Date) -> ContextCheckpointState {
    ContextCheckpointState(
      fired: [], peakTokens: 0, lastTokens: 0, compactionID: nil, modelID: nil, muted: false,
      transcriptPath: nil, project: nil, pendingProcessID: nil, updatedAt: now)
  }
}

extension ContextCheckpointState {
  private enum CodingKeys: String, CodingKey {
    case fired, peakTokens, lastTokens, compactionID, modelID, muted, transcriptPath, project
    case pendingProcessID, updatedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fresh = ContextCheckpointState.fresh(now: Date(timeIntervalSince1970: 0))
    self.init(
      fired: try container.decodeIfPresent([ContextLevel].self, forKey: .fired) ?? fresh.fired,
      peakTokens: try container.decodeIfPresent(Int.self, forKey: .peakTokens)
        ?? fresh.peakTokens,
      lastTokens: try container.decodeIfPresent(Int.self, forKey: .lastTokens)
        ?? fresh.lastTokens,
      compactionID: try container.decodeIfPresent(String.self, forKey: .compactionID),
      modelID: try container.decodeIfPresent(String.self, forKey: .modelID),
      muted: try container.decodeIfPresent(Bool.self, forKey: .muted) ?? fresh.muted,
      transcriptPath: try container.decodeIfPresent(String.self, forKey: .transcriptPath),
      project: try container.decodeIfPresent(String.self, forKey: .project),
      pendingProcessID: try container.decodeIfPresent(Int32.self, forKey: .pendingProcessID),
      updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? fresh.updatedAt)
  }
}

public struct ContextCheckpointStore: Sendable {
  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public static func isValidSessionID(_ id: String) -> Bool {
    !id.isEmpty
      && id.unicodeScalars.allSatisfy { scalar in
        (scalar.value >= 0x30 && scalar.value <= 0x39)
          || (scalar.value >= 0x41 && scalar.value <= 0x5A)
          || (scalar.value >= 0x61 && scalar.value <= 0x7A)
          || scalar == "-"
      }
  }

  public func load(sessionID: String) -> ContextCheckpointState? {
    guard Self.isValidSessionID(sessionID),
      let data = try? Data(contentsOf: stateFile(sessionID))
    else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(ContextCheckpointState.self, from: data)
  }

  public func sessionIDs() -> [String] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []
    return contents.filter { $0.pathExtension == "json" }
      .map { $0.deletingPathExtension().lastPathComponent }
      .filter { Self.isValidSessionID($0) }
      .sorted()
  }

  public func save(_ state: ContextCheckpointState, sessionID: String) throws {
    guard Self.isValidSessionID(sessionID) else {
      throw POSIXError(.EINVAL)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let target = stateFile(sessionID)
    let temporary = directory.appendingPathComponent(
      ".\(target.lastPathComponent).countersign-\(UUID().uuidString).tmp")
    try encoder.encode(state).write(to: temporary)
    guard rename(temporary.path, target.path) == 0 else {
      let code = errno
      unlink(temporary.path)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  public func withLock<T>(
    sessionID: String, attempts: Int = 20, interval: TimeInterval = 0.05, _ body: () throws -> T
  ) rethrows -> T? {
    guard Self.isValidSessionID(sessionID) else { return nil }
    let lastAttempt = max(attempts, 1) - 1
    for attempt in 0...lastAttempt {
      if let lock = try? ExclusiveFileLock.acquire(lockFile(sessionID)) {
        defer { lock.release() }
        return try body()
      }
      if attempt < lastAttempt {
        Thread.sleep(forTimeInterval: interval)
      }
    }
    return nil
  }

  public func prune(olderThan age: TimeInterval, now: Date) {
    let cutoff = now.addingTimeInterval(-age)
    for file in managedFiles() {
      let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
        .contentModificationDate
      if let modified, modified < cutoff {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }

  public func removeAll() {
    for file in managedFiles() {
      try? FileManager.default.removeItem(at: file)
    }
  }

  private func managedFiles() -> [URL] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    return contents.filter { $0.pathExtension == "json" || $0.pathExtension == "lock" }
  }

  private func stateFile(_ sessionID: String) -> URL {
    directory.appendingPathComponent("\(sessionID).json")
  }

  private func lockFile(_ sessionID: String) -> URL {
    directory.appendingPathComponent("\(sessionID).lock")
  }
}
