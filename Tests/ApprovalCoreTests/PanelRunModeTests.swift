import Testing

@testable import ApprovalCore

@Suite struct PanelRunModeTests {
  @Test func aHookFollowsItsChatAndHonorsPauseQuietTimeAndTheTimeout() {
    let mode = PanelRunMode.hook

    #expect(!mode.isTest)
    #expect(mode.followsChat)
    #expect(mode.honorsPause)
    #expect(mode.honorsQuietTime)
    #expect(mode.handsBackBeforeTimeout)
  }

  @Test func aHookWaitsOutTheGracePeriodItsTurnAndAPauseAndNeverYields() {
    let mode = PanelRunMode.hook

    #expect(mode.honorsGracePeriod)
    #expect(mode.waitsItsTurn)
    #expect(mode.waitsForIdleOnArrival)
    #expect(!mode.yieldsToOtherRequests)
  }

  @Test(arguments: TestPanelKind.allCases)
  func aTestPanelSkipsTheChatPauseQuietTimeAndTheTimeout(_ kind: TestPanelKind) {
    let mode = PanelRunMode.test(kind)

    #expect(mode.isTest)
    #expect(!mode.followsChat)
    #expect(!mode.honorsPause)
    #expect(!mode.honorsQuietTime)
    #expect(!mode.handsBackBeforeTimeout)
  }

  @Test(arguments: TestPanelKind.allCases)
  func aTestPanelShowsAtOnceAndYieldsToAnyOtherRequest(_ kind: TestPanelKind) {
    let mode = PanelRunMode.test(kind)

    #expect(!mode.honorsGracePeriod)
    #expect(!mode.waitsItsTurn)
    #expect(!mode.waitsForIdleOnArrival)
    #expect(mode.yieldsToOtherRequests)
  }

  @Test func aCheckpointWaitsItsTurnAndForIdleButSkipsChatGraceAndTimeout() {
    let mode = PanelRunMode.checkpoint

    #expect(!mode.isTest)
    #expect(!mode.followsChat)
    #expect(mode.honorsPause)
    #expect(mode.honorsQuietTime)
    #expect(!mode.handsBackBeforeTimeout)
    #expect(!mode.honorsGracePeriod)
    #expect(mode.waitsItsTurn)
    #expect(mode.waitsForIdleOnArrival)
    #expect(!mode.yieldsToOtherRequests)
  }

  @Test func onlyACheckpointSkipsHandoffAppsAndWaitsForApprovals() {
    #expect(!PanelRunMode.checkpoint.usesHandoffApps)
    #expect(PanelRunMode.checkpoint.waitsForApprovalsFirst)
    #expect(PanelRunMode.hook.usesHandoffApps)
    #expect(!PanelRunMode.hook.waitsForApprovalsFirst)
    #expect(PanelRunMode.test(.command).usesHandoffApps)
    #expect(!PanelRunMode.test(.command).waitsForApprovalsFirst)
  }

  @Test func modesCompareByKind() {
    #expect(PanelRunMode.test(.command) == .test(.command))
    #expect(PanelRunMode.test(.command) != .test(.plan))
    #expect(PanelRunMode.test(.question) != .hook)
  }
}
