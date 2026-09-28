import Foundation
import Testing

@testable import ApprovalCore

@Suite struct UpdateCheckAnswerTests {
  @Test func upToDate() {
    let answer = UpdateCheckAnswer.answer(
      for: .upToDate, currentVersion: "0.1.0", upgradeCommand: "brew upgrade countersign",
      releaseNotesURL: nil)

    #expect(answer.title == "Countersign is up to date")
    #expect(answer.message == "You have 0.1.0, the newest release.")
    #expect(answer.buttons == [.ok])
  }

  @Test func newerAvailableWithReleaseNotes() throws {
    let releaseNotesURL = try #require(
      URL(string: "https://github.com/Gord1y/countersign/releases/tag/v0.2.0"))
    let answer = UpdateCheckAnswer.answer(
      for: .newerAvailable(version: "0.2.0"), currentVersion: "0.1.0",
      upgradeCommand: "brew upgrade countersign", releaseNotesURL: releaseNotesURL)

    #expect(answer.title == "Countersign 0.2.0 is available")
    #expect(
      answer.message == "You have 0.1.0. To update, run:\nbrew upgrade countersign")
    #expect(
      answer.buttons == [
        .copyUpgradeCommand("brew upgrade countersign"), .openReleaseNotes(releaseNotesURL),
        .later,
      ])
  }

  @Test func newerAvailableWithoutReleaseNotesHasNoReleaseNotesButton() {
    let answer = UpdateCheckAnswer.answer(
      for: .newerAvailable(version: "0.2.0"), currentVersion: "0.1.0",
      upgradeCommand: "brew upgrade countersign", releaseNotesURL: nil)

    #expect(answer.buttons == [.copyUpgradeCommand("brew upgrade countersign"), .later])
  }

  @Test func unknown() {
    let answer = UpdateCheckAnswer.answer(
      for: .unknown(reason: "HTTP 404"), currentVersion: "0.1.0",
      upgradeCommand: "brew upgrade countersign", releaseNotesURL: nil)

    #expect(answer.title == "Couldn't check for updates")
    #expect(
      answer.message
        == "The list of releases couldn't be read (HTTP 404). Check your connection and try again later."
    )
    #expect(answer.buttons == [.ok])
  }

  @Test func buttonTitles() throws {
    let releaseNotesURL = try #require(
      URL(string: "https://github.com/Gord1y/countersign/releases/tag/v0.2.0"))

    #expect(UpdateCheckAnswerButton.ok.title == "OK")
    #expect(UpdateCheckAnswerButton.copyUpgradeCommand("x").title == "Copy Upgrade Command")
    #expect(UpdateCheckAnswerButton.openReleaseNotes(releaseNotesURL).title == "Release Notes")
    #expect(UpdateCheckAnswerButton.later.title == "Later")
  }
}
