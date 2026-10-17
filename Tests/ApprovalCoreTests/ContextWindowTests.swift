import Testing

@testable import ApprovalCore

@Suite struct ContextWindowTests {
  @Test(
    arguments: [
      "claude-opus-5-5", "claude-opus-4-7", "claude-sonnet-5", "claude-fable-5-1",
      "claude-haiku-5-5", "claude-opus-4-6[1m]", "us.anthropic.claude-opus-5-5-v1",
    ])
  func modelsWithADefaultMillionWindow(modelID: String) {
    #expect(
      ContextWindow.hasMillionTokens(modelID: modelID, tokens: 50_000, millionDisabled: false))
  }

  @Test(
    arguments: [
      "claude-opus-4-6", "claude-opus-4-5-20251101", "claude-opus-4-20250514",
      "claude-sonnet-4-6", "claude-sonnet-4-20250514", "claude-haiku-4-5",
      "claude-3-5-sonnet-20241022", "claude-instant-1.2",
      "us.anthropic.claude-opus-4-6-v1",
    ])
  func modelsThatPredateTheDefaultMillionWindow(modelID: String) {
    #expect(
      !ContextWindow.hasMillionTokens(modelID: modelID, tokens: 50_000, millionDisabled: false))
  }

  @Test func anUnknownModelKeepsTheStandardWindow() {
    #expect(!ContextWindow.hasMillionTokens(modelID: nil, tokens: 50_000, millionDisabled: false))
  }

  @Test func disablingMillionMakesADefaultMillionModelStandard() {
    #expect(
      !ContextWindow.hasMillionTokens(
        modelID: "claude-opus-5-5", tokens: 50_000, millionDisabled: true))
  }

  @Test(arguments: ["claude-opus-5-5", "claude-haiku-4-5", nil])
  func tokensAboveTheStandardWindowAreMillionEvenWhenDisabled(modelID: String?) {
    #expect(
      ContextWindow.hasMillionTokens(modelID: modelID, tokens: 200_001, millionDisabled: true))
    #expect(
      !ContextWindow.hasMillionTokens(
        modelID: "claude-haiku-4-5", tokens: 200_000, millionDisabled: true))
  }

  @Test(arguments: ["1", "TRUE", " yes ", "true"])
  func recognisesTheDisableValues(value: String) {
    let environment = [ContextWindow.disableMillionVariable: value]
    #expect(ContextWindow.isMillionDisabled(environment: environment))
  }

  @Test(arguments: ["0", "", "false", "no"])
  func ignoresOtherValues(value: String) {
    let environment = [ContextWindow.disableMillionVariable: value]
    #expect(!ContextWindow.isMillionDisabled(environment: environment))
  }

  @Test func ignoresAnAbsentVariable() {
    #expect(!ContextWindow.isMillionDisabled(environment: [:]))
  }
}
