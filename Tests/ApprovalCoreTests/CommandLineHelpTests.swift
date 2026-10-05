import Testing

@testable import ApprovalCore

@Suite struct CommandLineHelpTests {
  static let commands = [
    "setup", "settings", "doctor", "status", "pause", "resume", "snooze", "test-panel", "help",
    "--version",
  ]

  @Test func startsWithTheCountersignVersion() {
    #expect(CommandLineHelp.text(version: "1.2.3").hasPrefix("Countersign 1.2.3:"))
  }

  @Test func listsEveryCommandAtTheStartOfALine() {
    let lines = CommandLineHelp.text(version: "1.2.3").components(separatedBy: "\n")
    for command in Self.commands {
      #expect(lines.contains { $0.hasPrefix("  \(command)") })
    }
  }

  @Test func theTestPanelLineNamesEveryKind() throws {
    let lines = CommandLineHelp.text(version: "1.2.3").components(separatedBy: "\n")
    let line = try #require(lines.first { $0.hasPrefix("  test-panel") })
    #expect(line.contains("command, question, plan or context"))
  }

  @Test func containsEveryCompanionMenuURLAndTheBugFormURL() throws {
    let text = CommandLineHelp.text(version: "1.2.3")
    let documentationURL = try #require(CompanionMenu.documentationURL)
    let askAQuestionURL = try #require(CompanionMenu.askAQuestionURL)
    let contactDeveloperURL = try #require(CompanionMenu.contactDeveloperURL)
    let sponsorURL = try #require(CompanionMenu.sponsorURL)
    let buyMeACoffeeURL = try #require(CompanionMenu.buyMeACoffeeURL)
    let formURL = try #require(BugReportURL.formURL)
    #expect(text.contains(documentationURL.absoluteString))
    #expect(text.contains(askAQuestionURL.absoluteString))
    #expect(text.contains(contactDeveloperURL.absoluteString))
    #expect(text.contains(sponsorURL.absoluteString))
    #expect(text.contains(buyMeACoffeeURL.absoluteString))
    #expect(text.contains(formURL.absoluteString))
  }

  @Test func neverWrapsPastAHundredCharacters() {
    let lines = CommandLineHelp.text(version: "1.2.3").components(separatedBy: "\n")
    for line in lines {
      #expect(line.count <= 100)
    }
  }
}
