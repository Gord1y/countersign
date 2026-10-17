import Foundation

public struct ContextGauge: Sendable, Equatable {
  public var tokens: Int
  public var windowTokens: Int
  public var windowPercent: Int
  public var modelID: String?
  public var ladder: [Int]
  public var passed: [ContextLevel]
  public var warmth: ContextWarmth

  public init(
    tokens: Int, windowTokens: Int, windowPercent: Int, modelID: String?, ladder: [Int],
    passed: [ContextLevel], warmth: ContextWarmth
  ) {
    self.tokens = tokens
    self.windowTokens = windowTokens
    self.windowPercent = windowPercent
    self.modelID = modelID
    self.ladder = ladder
    self.passed = passed
    self.warmth = warmth
  }

  public static func make(
    reading: ContextReading?, state: ContextCheckpointState?, settings: ContextCheckpointSettings,
    now: Date
  ) -> ContextGauge? {
    guard let tokens = reading?.tokens ?? state?.lastTokens else { return nil }
    let readingWindow = reading?.hasMillionTokenWindow == true ? true : nil
    let hasMillionWindow =
      tokens > ContextUsageReader.standardWindowTokens
      || state?.hasMillionTokenWindow ?? readingWindow
        ?? ContextWindow.hasMillionTokens(
          modelID: state?.modelID ?? reading?.modelID, tokens: tokens, millionDisabled: false)
    let windowTokens =
      hasMillionWindow
      ? ContextUsageReader.millionWindowTokens : ContextUsageReader.standardWindowTokens
    let modelID = state?.modelID ?? reading?.modelID
    let ladder = ContextLadder.thresholds(
      modelID: modelID, hasMillionTokenWindow: hasMillionWindow,
      settings: ContextLadderSettings(settings))
    let passed = zip(ContextLevel.allCases, ladder).filter { tokens >= $0.1 }.map(\.0)
    return ContextGauge(
      tokens: tokens, windowTokens: windowTokens,
      windowPercent: Int((Double(tokens) * 100 / Double(windowTokens)).rounded()),
      modelID: modelID, ladder: ladder, passed: passed,
      warmth: reading.map { ContextWarmth.of($0, now: now) } ?? .unknown)
  }
}
