import Foundation
import Testing

@testable import ApprovalCore

@Suite struct SetupFlowTests {
  private let update = HostWiringStatus.needsUpdate(HostWiringUpdate(otherExecutablePaths: []))

  @Test func nothingInstalledMeansNoAgents() {
    let agents = SetupAgents(
      statuses: [
        .claude: .notInstalled, .codex: .notInstalled, .cursor: .notInstalled,
        .antigravity: .notInstalled,
      ])
    #expect(agents.phase == .noAgents)
    #expect(agents.notInstalled == Host.allCases)
  }

  @Test func notWiredAndOutdatedAgentsAreWiredTogether() {
    let agents = SetupAgents(
      statuses: [
        .claude: .wired, .codex: .notWired, .cursor: update, .antigravity: .notInstalled,
      ])
    #expect(agents.phase == .needsWiring)
    #expect(agents.toWire == [.codex, .cursor])
    #expect(agents.wired == [.claude])
  }

  @Test func anUnusableAgentSitsBesideAllSet() {
    let agents = SetupAgents(
      statuses: [
        .claude: .wired, .codex: .unusable("unreadable"), .cursor: .notInstalled,
        .antigravity: .notInstalled,
      ])
    #expect(agents.phase == .allSet)
    #expect(agents.unusable == [.codex])
  }

  @Test func aLoneUnusableAgentIsFoundSoNotNoAgents() {
    let agents = SetupAgents(
      statuses: [
        .claude: .notInstalled, .codex: .notInstalled, .cursor: .unusable("unreadable"),
        .antigravity: .notInstalled,
      ])
    #expect(agents.phase == .allSet)
    #expect(agents.wired.isEmpty)
    #expect(agents.unusable == [.cursor])
  }

  @Test func setupOpensOnlyWhenNeitherSetupNorTourWasShown() {
    #expect(SetupLaunch.opensSetup(setupShown: false, tourShown: false))
    #expect(!SetupLaunch.opensSetup(setupShown: true, tourShown: false))
    #expect(!SetupLaunch.opensSetup(setupShown: false, tourShown: true))
    #expect(!SetupLaunch.opensSetup(setupShown: true, tourShown: true))
  }

  @Test func setupShownFileSitsNextToTourShownFile() {
    let paths = AppPaths(home: URL(fileURLWithPath: "/Users/dev"))
    #expect(paths.setupShownFile.lastPathComponent == "setup-shown")
    #expect(
      paths.setupShownFile.deletingLastPathComponent()
        == paths.tourShownFile.deletingLastPathComponent())
  }
}
