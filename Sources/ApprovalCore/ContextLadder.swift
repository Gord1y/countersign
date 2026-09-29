import Foundation

public enum ContextLevel: Int, Sendable, Codable, CaseIterable, Comparable {
  case soft = 1
  case status
  case insist

  public static func < (lhs: ContextLevel, rhs: ContextLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct ContextLadderSettings: Sendable, Equatable {
  public var standardThresholds: [Int]
  public var millionThresholds: [Int]
  public var modelThresholds: [String: [Int]]
  public var rearmBelow: Double

  public init(
    standardThresholds: [Int], millionThresholds: [Int], modelThresholds: [String: [Int]],
    rearmBelow: Double
  ) {
    self.standardThresholds = standardThresholds
    self.millionThresholds = millionThresholds
    self.modelThresholds = modelThresholds
    self.rearmBelow = rearmBelow
  }

  public static let defaultStandardThresholds = [100_000, 130_000, 160_000]
  public static let defaultMillionThresholds = [200_000, 300_000, 400_000]
  public static let defaultRearmBelow = 0.6

  public static let `default` = ContextLadderSettings(
    standardThresholds: defaultStandardThresholds, millionThresholds: defaultMillionThresholds,
    modelThresholds: [:], rearmBelow: defaultRearmBelow)
}

public struct ContextLadderStep: Sendable, Equatable {
  public var state: ContextCheckpointState
  public var fire: ContextLevel?
}

public enum ContextLadder {
  public static func thresholds(
    modelID: String?, hasMillionTokenWindow: Bool, settings: ContextLadderSettings
  ) -> [Int] {
    if let modelID,
      let prefix = settings.modelThresholds.keys.filter({ modelID.hasPrefix($0) })
        .max(by: { $0.count < $1.count }),
      let ladder = settings.modelThresholds[prefix]
    {
      return ladder
    }
    return hasMillionTokenWindow ? settings.millionThresholds : settings.standardThresholds
  }

  public static func step(
    tokens: Int, modelID: String?, hasMillionTokenWindow: Bool, compactionID: String?,
    previous: ContextCheckpointState, settings: ContextLadderSettings
  ) -> ContextLadderStep {
    var state = previous
    let compacted = compactionID != nil && compactionID != previous.compactionID
    let collapsed = Double(tokens) < settings.rearmBelow * Double(previous.peakTokens)
    if compacted || collapsed {
      state.fired = []
      state.peakTokens = tokens
    }
    state.peakTokens = max(state.peakTokens, tokens)
    state.lastTokens = tokens
    state.modelID = modelID ?? previous.modelID
    state.compactionID = compactionID ?? previous.compactionID

    guard !state.muted else { return ContextLadderStep(state: state, fire: nil) }

    let ladder = thresholds(
      modelID: state.modelID, hasMillionTokenWindow: hasMillionTokenWindow, settings: settings)
    let crossed = zip(ContextLevel.allCases, ladder).filter { tokens >= $0.1 }.map(\.0).max()
    guard let crossed, state.fired.allSatisfy({ $0 < crossed }) else {
      return ContextLadderStep(state: state, fire: nil)
    }
    state.fired = ContextLevel.allCases.filter { $0 <= crossed }
    return ContextLadderStep(state: state, fire: crossed)
  }
}
