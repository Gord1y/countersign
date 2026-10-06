import Foundation
import Testing

@testable import ApprovalCore

@Suite struct UpdateCommandTests {
  @Test(
    arguments: [
      "/opt/homebrew/bin/countersign",
      "/usr/local/bin/countersign",
      "/opt/homebrew/Cellar/countersign/0.1.0/bin/countersign",
    ])
  func offersBrewUpgradeForAHomebrewInstall(path: String) {
    #expect(UpdateCommand.upgrade(forStablePath: path) == UpdateCommand.brewUpgradeCommand)
  }

  @Test(
    arguments: [
      "/Users/dev/.local/bin/countersign",
      "/Applications/Countersign.app/Contents/MacOS/countersign",
    ])
  func offersTheCurlInstallerOutsideHomebrew(path: String) {
    #expect(UpdateCommand.upgrade(forStablePath: path) == UpdateCommand.curlInstallCommand)
  }

  @Test func buildsTheReleaseNotesURLFromTheVersion() {
    #expect(
      UpdateCommand.releaseNotesURL(version: "0.2.0")?.absoluteString
        == "https://github.com/Gord1y/countersign/releases/tag/v0.2.0")
  }
}
