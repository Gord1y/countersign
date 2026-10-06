import Testing

@testable import ApprovalCore

@Suite struct CommandHelpTests {
  @Test func aLoneHelpFlagIsARequest() {
    #expect(CommandHelp.isRequest(["--help"]))
    #expect(CommandHelp.isRequest(["-h"]))
  }

  @Test func anythingElseIsNotARequest() {
    #expect(!CommandHelp.isRequest([]))
    #expect(!CommandHelp.isRequest(["help"]))
    #expect(!CommandHelp.isRequest(["--HELP"]))
    #expect(!CommandHelp.isRequest(["--help", "x"]))
    #expect(!CommandHelp.isRequest(["x", "--help"]))
  }
}
