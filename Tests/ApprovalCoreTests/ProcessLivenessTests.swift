import Darwin
import Testing

@testable import ApprovalCore

@Suite struct ProcessLivenessTests {
  @Test func parentPIDOfTheTestProcessMatchesGetppid() {
    #expect(ProcessLiveness.parentPID(of: getpid()) == getppid())
  }

  @Test func parentPIDIsNilForANonPositivePID() {
    #expect(ProcessLiveness.parentPID(of: 0) == nil)
    #expect(ProcessLiveness.parentPID(of: -1) == nil)
  }

  @Test func parentPIDIsNilForAPIDThatDoesNotExist() {
    #expect(ProcessLiveness.parentPID(of: 999_999) == nil)
  }
}
