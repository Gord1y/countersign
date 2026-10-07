import Testing

@testable import ApprovalCore

@Suite struct CommandHelpTests {
  @Test func aLoneHelpFlagIsARequest() {
    #expect(CommandHelp.isRequest(["--help"]))
    #expect(CommandHelp.isRequest(["-h"]))
  }

  @Test func aHelpFlagAnywhereAmongTheArgumentsIsARequest() {
    #expect(CommandHelp.isRequest(["--cli", "--help"]))
    #expect(CommandHelp.isRequest(["plan", "--help"]))
    #expect(CommandHelp.isRequest(["15m", "-h"]))
    #expect(CommandHelp.isRequest(["--help", "x"]))
    #expect(CommandHelp.isRequest(["x", "--help", "y"]))
  }

  @Test func anythingElseIsNotARequest() {
    #expect(!CommandHelp.isRequest([]))
    #expect(!CommandHelp.isRequest(["help"]))
    #expect(!CommandHelp.isRequest(["--HELP"]))
    #expect(!CommandHelp.isRequest(["--cli"]))
    #expect(!CommandHelp.isRequest(["--helpful"]))
  }
}
