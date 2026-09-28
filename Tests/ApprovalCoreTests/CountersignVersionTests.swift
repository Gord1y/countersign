import Testing

@testable import ApprovalCore

@Suite struct CountersignVersionTests {
  @Test func currentIsTheReleasedVersion() {
    #expect(CountersignVersion.current == "0.1.0")
  }
}
