import Foundation
import Testing

@testable import ApprovalCore

struct InfoCommandTextTests {
  private func availability(notes: URL?) -> UpdateAvailability {
    UpdateAvailability(
      version: "0.7.0", upgradeCommand: "brew upgrade countersign", releaseNotesURL: notes)
  }

  @Test func upToDateNamesTheCurrentVersion() {
    let lines = UpdateCheckCommandText.lines(
      outcome: .upToDate, currentVersion: "0.6.0", availability: nil)
    #expect(lines == ["up to date (0.6.0)"])
  }

  @Test func newerReleaseListsUpgradeAndNotes() {
    let notes = URL(string: "https://example.com/notes")
    let lines = UpdateCheckCommandText.lines(
      outcome: .newerAvailable(version: "0.7.0"), currentVersion: "0.6.0",
      availability: availability(notes: notes))
    #expect(
      lines == [
        "update available: 0.7.0", "upgrade: brew upgrade countersign",
        "release notes: https://example.com/notes",
      ])
  }

  @Test func newerReleaseWithoutNotesOmitsTheNotesLine() {
    let lines = UpdateCheckCommandText.lines(
      outcome: .newerAvailable(version: "0.7.0"), currentVersion: "0.6.0",
      availability: availability(notes: nil))
    #expect(lines == ["update available: 0.7.0", "upgrade: brew upgrade countersign"])
  }

  @Test func unknownReportsTheReason() {
    let lines = UpdateCheckCommandText.lines(
      outcome: .unknown(reason: "HTTP 500"), currentVersion: "0.6.0", availability: nil)
    #expect(lines == ["error: could not check for updates: HTTP 500"])
  }

  @Test func onlyUnknownFails() {
    #expect(UpdateCheckCommandText.succeeded(.upToDate))
    #expect(UpdateCheckCommandText.succeeded(.newerAvailable(version: "0.7.0")))
    #expect(!UpdateCheckCommandText.succeeded(.unknown(reason: "offline")))
  }
}
