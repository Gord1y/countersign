import Testing

@testable import ApprovalCore

@Suite struct TestCardCommandLineTests {
  @Test func parsesNotice() {
    #expect(TestCardCommandLine.parse(["notice"]) == .notice)
  }

  @Test func parsesApproval() {
    #expect(TestCardCommandLine.parse(["approval"]) == .approval)
  }

  @Test func refusesNoArguments() {
    #expect(TestCardCommandLine.parse([]) == nil)
  }

  @Test func refusesAnUnknownKind() {
    #expect(TestCardCommandLine.parse(["bogus"]) == nil)
  }

  @Test func refusesExtraArguments() {
    #expect(TestCardCommandLine.parse(["notice", "extra"]) == nil)
  }
}
