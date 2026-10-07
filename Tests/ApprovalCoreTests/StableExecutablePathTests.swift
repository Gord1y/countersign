import Foundation
import Testing

@testable import ApprovalCore

@Suite struct StableExecutablePathTests {
  let home = URL(fileURLWithPath: "/Users/dev")
  let cliPath = "/Users/dev/.local/bin/countersign"

  @Test func usesHomebrewsLinkForAnAppleSiliconCellar() {
    #expect(
      StableExecutablePath.stable(
        forResolved: "/opt/homebrew/Cellar/countersign/0.1.0/bin/countersign", home: home,
        isExecutable: { _ in false })
        == "/opt/homebrew/bin/countersign")
  }

  @Test func usesHomebrewsLinkForAnIntelCellar() {
    #expect(
      StableExecutablePath.stable(
        forResolved: "/usr/local/Cellar/countersign/0.2.1_1/bin/countersign", home: home,
        isExecutable: { _ in false })
        == "/usr/local/bin/countersign")
  }

  @Test func usesHomebrewsLinkForAnAppBundleInsideACellar() {
    #expect(
      StableExecutablePath.stable(
        forResolved:
          "/opt/homebrew/Cellar/countersign/0.1.0/Countersign.app/Contents/MacOS/countersign",
        home: home, isExecutable: { _ in false })
        == "/opt/homebrew/bin/countersign")
  }

  @Test func homebrewWinsOverAnExecutableCliInTheCellarCase() {
    #expect(
      StableExecutablePath.stable(
        forResolved:
          "/opt/homebrew/Cellar/countersign/0.1.0/Countersign.app/Contents/MacOS/countersign",
        home: home, isExecutable: { _ in true })
        == "/opt/homebrew/bin/countersign")
  }

  @Test func mapsAnAppInApplicationsToAnExecutableCli() {
    let path = "/Applications/Countersign.app/Contents/MacOS/countersign"
    #expect(
      StableExecutablePath.stable(forResolved: path, home: home, isExecutable: { _ in true })
        == cliPath)
  }

  @Test func mapsAnAppInHomeApplicationsToAnExecutableCli() {
    let path = "/Users/dev/Applications/Countersign.app/Contents/MacOS/countersign"
    #expect(
      StableExecutablePath.stable(forResolved: path, home: home, isExecutable: { _ in true })
        == cliPath)
  }

  @Test func mapsACopiedAppToAppleSiliconHomebrewWhenThereIsNoUserCli() {
    let path = "/Users/dev/Applications/Countersign.app/Contents/MacOS/countersign"
    #expect(
      StableExecutablePath.stable(
        forResolved: path, home: home, isExecutable: { $0 == "/opt/homebrew/bin/countersign" })
        == "/opt/homebrew/bin/countersign")
  }

  @Test func mapsACopiedAppToIntelHomebrewWhenItIsTheOnlyCli() {
    let path = "/Users/dev/Applications/Countersign.app/Contents/MacOS/countersign"
    #expect(
      StableExecutablePath.stable(
        forResolved: path, home: home, isExecutable: { $0 == "/usr/local/bin/countersign" })
        == "/usr/local/bin/countersign")
  }

  @Test func keepsTheUserCliAheadOfHomebrewForACopiedApp() {
    let path = "/Users/dev/Applications/Countersign.app/Contents/MacOS/countersign"
    #expect(
      StableExecutablePath.stable(
        forResolved: path, home: home,
        isExecutable: { $0 == cliPath || $0 == "/opt/homebrew/bin/countersign" })
        == cliPath)
  }

  @Test func keepsTheCopiedAppWhenNoCliIsExecutable() {
    let path = "/Users/dev/Applications/Countersign.app/Contents/MacOS/countersign"
    #expect(
      StableExecutablePath.stable(forResolved: path, home: home, isExecutable: { _ in false })
        == path)
  }

  @Test func keepsAnAppBundleOutsideACellarWhenTheCliIsMissingOrNotExecutable() {
    let path = "/Applications/Countersign.app/Contents/MacOS/countersign"
    #expect(
      StableExecutablePath.stable(forResolved: path, home: home, isExecutable: { _ in false })
        == path)
  }

  @Test func keepsAUserInstall() {
    #expect(
      StableExecutablePath.stable(forResolved: cliPath, home: home, isExecutable: { _ in true })
        == cliPath)
  }

  @Test func keepsAPathThatOnlyMentionsACellar() {
    let path = "/Users/dev/Cellar/other/bin/countersign"
    #expect(
      StableExecutablePath.stable(forResolved: path, home: home, isExecutable: { _ in true })
        == path)
  }

  @Test func keepsANonBundleBinaryEvenWhenTheCliExists() {
    let path = "/Users/dev/src/countersign/.build/debug/countersign"
    #expect(
      StableExecutablePath.stable(forResolved: path, home: home, isExecutable: { _ in true })
        == path)
  }

  @Test func keepsAPathWithAFolderNamedLikeTheAppThatIsNotTheBundleBinary() {
    let path = "/Users/dev/Countersign.app/notes/countersign"
    #expect(
      StableExecutablePath.stable(forResolved: path, home: home, isExecutable: { _ in true })
        == path)
  }

  @Test func asksWhetherTheCliPathIsExecutable() {
    var asked: [String] = []
    _ = StableExecutablePath.stable(
      forResolved: "/Applications/Countersign.app/Contents/MacOS/countersign", home: home,
      isExecutable: {
        asked.append($0)
        return true
      })
    #expect(asked == [cliPath])
  }
}
