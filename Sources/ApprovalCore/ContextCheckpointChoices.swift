import Foundation

public struct ContextCheckpointChoices: Sendable, Equatable {
  public var soft: [ContextCheckpointChoice]
  public var status: [ContextCheckpointChoice]
  public var insist: [ContextCheckpointChoice]

  public static let levelNames = ["soft", "status", "insist"]
  public static let canonicalOrder: [ContextCheckpointChoice] = [
    .compactAfterStep, .handOff, .continueWorking, .notThisSession,
  ]
  public static let maximumCount = 4

  public static let `default` = ContextCheckpointChoices(
    soft: [.continueWorking, .compactAfterStep, .notThisSession],
    status: [.handOff, .compactAfterStep, .continueWorking],
    insist: [.handOff, .compactAfterStep, .continueWorking])

  public init(
    soft: [ContextCheckpointChoice], status: [ContextCheckpointChoice],
    insist: [ContextCheckpointChoice]
  ) {
    self.soft = soft
    self.status = status
    self.insist = insist
  }

  public func list(for level: ContextLevel) -> [ContextCheckpointChoice] {
    switch level {
    case .soft: return soft
    case .status: return status
    case .insist: return insist
    case .stop: return []
    }
  }

  public func offered(at level: ContextLevel, compactions: Int, maxCompactions: Int)
    -> [ContextCheckpointChoice]
  {
    let configured = list(for: level)
    guard !configured.isEmpty else { return [] }
    guard compactions >= maxCompactions else { return configured }
    let withoutCompact = configured.filter { $0 != .compactAfterStep }
    return withoutCompact.isEmpty ? [.handOff, .continueWorking] : withoutCompact
  }

  public static func ordered(
    _ choices: Set<ContextCheckpointChoice>, highlighted: ContextCheckpointChoice
  ) -> [ContextCheckpointChoice] {
    let rest = canonicalOrder.filter { choices.contains($0) && $0 != highlighted }
    return choices.contains(highlighted) ? [highlighted] + rest : rest
  }

  func list(named name: String) -> [ContextCheckpointChoice]? {
    switch name {
    case "soft": return soft
    case "status": return status
    case "insist": return insist
    default: return nil
    }
  }
}
