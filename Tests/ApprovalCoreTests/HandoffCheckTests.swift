import Testing

@testable import ApprovalCore

@Suite struct HandoffCheckTests {
  @Test func listedFrontmostAppThatAskedHandsOff() {
    #expect(
      HandoffCheck.shouldHandOff(
        frontmostBundleID: "com.openai.codex", frontmostPID: 501,
        handoffApps: ["com.openai.codex"], hostAppPID: 501))
  }

  @Test func listedFrontmostAppThatDidNotAskKeepsThePanel() {
    #expect(
      !HandoffCheck.shouldHandOff(
        frontmostBundleID: "com.openai.codex", frontmostPID: 501,
        handoffApps: ["com.openai.codex"], hostAppPID: 777))
  }

  @Test func listedFrontmostAppHandsOffWhenTheAskingAppIsUnknown() {
    #expect(
      HandoffCheck.shouldHandOff(
        frontmostBundleID: "com.openai.codex", frontmostPID: 501,
        handoffApps: ["com.openai.codex"], hostAppPID: nil))
  }

  @Test func unlistedFrontmostAppKeepsThePanel() {
    #expect(
      !HandoffCheck.shouldHandOff(
        frontmostBundleID: "com.todesktop.230313mzl4w4u92", frontmostPID: 501,
        handoffApps: ["com.openai.codex"], hostAppPID: 501))
  }

  @Test func noFrontmostAppKeepsThePanel() {
    #expect(
      !HandoffCheck.shouldHandOff(
        frontmostBundleID: nil, frontmostPID: nil, handoffApps: ["com.openai.codex"],
        hostAppPID: 501))
  }
}
