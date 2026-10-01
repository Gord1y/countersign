import Testing

@testable import ApprovalCore

@Suite struct ApprovalCardTimingTests {
  struct Row: Sendable, CustomTestStringConvertible {
    let name: String
    var enabled = true
    var mode = PanelRunMode.hook
    var secondsWaiting = 5.0
    var quiet = false
    var paused = false
    var stage = ApprovalCardStage.notShown
    let expected: Bool

    var testDescription: String { name }
  }

  static let rows: [Row] = [
    Row(name: "before the delay", secondsWaiting: 4.9, expected: false),
    Row(name: "at the delay", secondsWaiting: 5, expected: true),
    Row(name: "after the delay", secondsWaiting: 120, expected: true),
    Row(name: "quiet time", quiet: true, expected: false),
    Row(name: "paused", paused: true, expected: false),
    Row(name: "already shown", stage: .shown, expected: false),
    Row(name: "dismissed", stage: .dismissed, expected: false),
    Row(name: "test panel", mode: .test(.command), expected: false),
    Row(name: "context checkpoint", mode: .checkpoint, expected: false),
    Row(name: "card off", enabled: false, expected: false),
  ]

  @Test(arguments: rows)
  func decides(row: Row) {
    let shows = ApprovalCardTiming.shouldShow(
      enabled: row.enabled, mode: row.mode, secondsWaiting: row.secondsWaiting, delay: 5,
      quiet: row.quiet, paused: row.paused, stage: row.stage)
    #expect(shows == row.expected)
  }
}
