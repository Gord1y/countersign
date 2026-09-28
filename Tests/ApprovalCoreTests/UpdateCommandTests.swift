import Foundation
import Testing

@testable import ApprovalCore

@Suite struct UpdateCommandTests {
  @Test func offersBrewUpgradeForAnAppleSiliconCellarInstall() {
    #expect(
      UpdateCommand.upgrade(
        forResolvedExecutablePath: "/opt/homebrew/Cellar/countersign/0.1.0/bin/countersign")
        == UpdateCommand.brewUpgradeCommand)
  }

  @Test func offersBrewUpgradeForAnIntelCellarInstall() {
    #expect(
      UpdateCommand.upgrade(
        forResolvedExecutablePath: "/usr/local/Cellar/countersign/0.1.0/bin/countersign")
        == UpdateCommand.brewUpgradeCommand)
  }

  @Test func offersTheCurlInstallerOutsideACellar() {
    #expect(
      UpdateCommand.upgrade(
        forResolvedExecutablePath: "/Applications/Countersign.app/Contents/MacOS/countersign")
        == UpdateCommand.curlInstallCommand)
  }

  @Test func offersTheCurlInstallerForAUserInstall() {
    #expect(
      UpdateCommand.upgrade(forResolvedExecutablePath: "/Users/dev/.local/bin/countersign")
        == UpdateCommand.curlInstallCommand)
  }

  @Test func buildsTheReleaseNotesURLFromTheVersion() {
    #expect(
      UpdateCommand.releaseNotesURL(version: "0.2.0")?.absoluteString
        == "https://github.com/Gord1y/countersign/releases/tag/v0.2.0")
  }
}
