import Darwin
import Foundation

public enum ContextCheckpointAbandonReason: String, Sendable, Equatable {
  case parentExited, compacted, superseded
}

public final class ContextCheckpointWatcher {
  public static let lookInterval: TimeInterval = 2

  private let transcriptURL: URL?
  private let sessionID: String
  private let processID: Int32
  private let store: ContextCheckpointStore
  private let baselineCompactionID: String?
  private let now: () -> Date
  private let parentPID: () -> Int32
  private let startingParentPID: Int32
  private var lastLookAt: Date
  private var lastSize: UInt64?
  private var reason: ContextCheckpointAbandonReason?

  public init(
    transcriptURL: URL?, sessionID: String, processID: Int32, store: ContextCheckpointStore,
    baselineCompactionID: String?, now: @escaping () -> Date = Date.init,
    parentPID: @escaping () -> Int32 = { getppid() }
  ) {
    self.transcriptURL = transcriptURL
    self.sessionID = sessionID
    self.processID = processID
    self.store = store
    self.baselineCompactionID = baselineCompactionID
    self.now = now
    self.parentPID = parentPID
    self.startingParentPID = parentPID()
    self.lastLookAt = now()
    self.lastSize = transcriptURL.flatMap(Self.size(of:))
  }

  public func poll() -> ContextCheckpointAbandonReason? {
    if let reason {
      return reason
    }
    let found = firstReason()
    reason = found
    return found
  }

  private func firstReason() -> ContextCheckpointAbandonReason? {
    if parentPID() != startingParentPID {
      return .parentExited
    }
    if let pending = store.load(sessionID: sessionID)?.pendingProcessID, pending != processID {
      return .superseded
    }
    return transcriptCompacted() ? .compacted : nil
  }

  private func transcriptCompacted() -> Bool {
    let current = now()
    guard current.timeIntervalSince(lastLookAt) >= Self.lookInterval else { return false }
    lastLookAt = current
    guard let transcriptURL, let size = Self.size(of: transcriptURL), size != lastSize else {
      return false
    }
    lastSize = size
    guard let compactionID = ContextUsageReader.read(transcriptURL: transcriptURL)?.compactionID
    else { return false }
    return compactionID != baselineCompactionID
  }

  private static func size(of url: URL) -> UInt64? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? NSNumber
    else { return nil }
    return size.uint64Value
  }
}
