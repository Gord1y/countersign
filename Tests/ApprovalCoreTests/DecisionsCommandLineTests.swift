import Testing

@testable import ApprovalCore

@Suite struct DecisionsCommandLineTests {
  @Test func noArgumentsListTheMenuLimit() {
    #expect(
      DecisionsCommandLine.parse([]) == .list(limit: CompanionMenu.recentDecisionLimit))
  }

  @Test func limitAcceptsWholeNumbersUpToTheKeptEntries() {
    #expect(DecisionsCommandLine.parse(["--limit", "50"]) == .list(limit: 50))
    #expect(DecisionsCommandLine.parse(["--limit", "200"]) == .list(limit: 200))
  }

  @Test func clearIsRecognised() {
    #expect(DecisionsCommandLine.parse(["clear"]) == .clear)
  }

  @Test func everythingElseIsRejected() {
    let rejected = [
      ["--limit", "0"], ["--limit", "201"], ["--limit", "abc"], ["--limit"], ["clear", "now"],
      ["bogus"],
    ]
    for arguments in rejected {
      #expect(DecisionsCommandLine.parse(arguments) == nil)
    }
  }
}
