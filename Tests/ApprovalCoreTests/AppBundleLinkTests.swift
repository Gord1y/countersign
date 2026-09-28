import Foundation
import Testing

@testable import ApprovalCore

private let home = URL(fileURLWithPath: "/Users/dev")
private let tarballBinary = "/Users/dev/Downloads/countersign-0.1.0/bin/countersign"
private let tarballApp = "/Users/dev/Downloads/countersign-0.1.0/Countersign.app"
private let bottleBinary = "/opt/homebrew/Cellar/countersign/0.1.0/bin/countersign"
private let bottleApp = "/opt/homebrew/Cellar/countersign/0.1.0/Countersign.app"

@Suite struct AppBundleLinkTests {
  @Test func looksNextToTheBinarysDirectory() {
    #expect(AppBundleLink.candidate(forResolvedExecutable: tarballBinary) == tarballApp)
    #expect(AppBundleLink.candidate(forResolvedExecutable: bottleBinary) == bottleApp)
    #expect(
      AppBundleLink.candidate(
        forResolvedExecutable: "/Applications/Countersign.app/Contents/MacOS/countersign")
        == "/Applications/Countersign.app/Contents/Countersign.app")
  }

  @Test func pointsABottleLinkAtHomebrewsOptDirectory() {
    #expect(
      AppBundleLink.stableTarget(for: bottleApp) == "/opt/homebrew/opt/countersign/Countersign.app")
    #expect(
      AppBundleLink.stableTarget(for: "/usr/local/Cellar/countersign/0.2.0_1/Countersign.app")
        == "/usr/local/opt/countersign/Countersign.app")
  }

  @Test func keepsEveryOtherTargetAsItIs() {
    #expect(AppBundleLink.stableTarget(for: tarballApp) == tarballApp)
    #expect(
      AppBundleLink.stableTarget(for: "/opt/homebrew/Cellar/countersign/0.1.0")
        == "/opt/homebrew/Cellar/countersign/0.1.0")
  }

  @Test func linksIntoTheUsersApplicationsFolder() {
    #expect(AppBundleLink.link(home: home).path == "/Users/dev/Applications/Countersign.app")
  }

  @Test func offersTheLinkOnlyWhenTheAppIsThereAndTheLinkIsNot() {
    let link = "/Users/dev/Applications/Countersign.app"
    #expect(
      AppBundleLink.offer(resolvedExecutable: bottleBinary, home: home) { $0 == bottleApp }
        == AppBundleLinkOffer(
          target: "/opt/homebrew/opt/countersign/Countersign.app",
          link: URL(fileURLWithPath: link)))
    #expect(
      AppBundleLink.offer(resolvedExecutable: tarballBinary, home: home) { $0 == tarballApp }?
        .target == tarballApp)
    #expect(AppBundleLink.offer(resolvedExecutable: bottleBinary, home: home) { _ in false } == nil)
    #expect(
      AppBundleLink.offer(resolvedExecutable: bottleBinary, home: home) {
        $0 == bottleApp || $0 == link
      } == nil)
  }
}
