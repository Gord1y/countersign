import CoreGraphics
import Testing

@testable import ApprovalCore

@Suite struct MissionControlTests {
  private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let externalOnTheRight = CGRect(x: 1512, y: -200, width: 2560, height: 1440)

  private func dock(layer: Int, bounds: CGRect) -> MissionControl.Window {
    MissionControl.Window(ownerName: "Dock", layer: layer, bounds: bounds)
  }

  @Test func showsWhenTheDockCoversADisplayAtTheOverlayLayer() {
    #expect(
      MissionControl.isShowing(windows: [dock(layer: 18, bounds: laptop)], displays: [laptop]))
  }

  @Test func showsWhenTheOverlayCoversTheSecondDisplayOnly() {
    #expect(
      MissionControl.isShowing(
        windows: [dock(layer: 18, bounds: externalOnTheRight)],
        displays: [laptop, externalOnTheRight]))
  }

  @Test func showsWhenTheOverlayLeavesTheMenuBarStripUncovered() {
    let belowTheMenuBar = CGRect(x: 0, y: 38, width: 1512, height: 944)
    #expect(
      MissionControl.isShowing(
        windows: [dock(layer: 18, bounds: belowTheMenuBar)], displays: [laptop]))
  }

  @Test func doesNotShowForAnOverlaySmallerThanNinetyPercentOfADisplay() {
    let half = CGRect(x: 0, y: 0, width: 756, height: 982)
    #expect(!MissionControl.isShowing(windows: [dock(layer: 18, bounds: half)], displays: [laptop]))
  }

  @Test func doesNotShowForTheRestingDockWallpaperAndDockWindows() {
    let resting = [
      dock(layer: -2_147_483_624, bounds: laptop),
      dock(layer: 20, bounds: laptop),
      dock(layer: 0, bounds: laptop),
    ]
    #expect(!MissionControl.isShowing(windows: resting, displays: [laptop]))
  }

  @Test func doesNotShowForAnotherOwnerAtTheOverlayLayer() {
    let other = MissionControl.Window(ownerName: "Finder", layer: 18, bounds: laptop)
    #expect(!MissionControl.isShowing(windows: [other], displays: [laptop]))
  }

  @Test func doesNotShowForAnOverlayOffEveryDisplay() {
    let offscreen = CGRect(x: 5000, y: 0, width: 1512, height: 982)
    #expect(
      !MissionControl.isShowing(windows: [dock(layer: 18, bounds: offscreen)], displays: [laptop]))
  }

  @Test func doesNotShowWithoutDisplays() {
    #expect(!MissionControl.isShowing(windows: [dock(layer: 18, bounds: laptop)], displays: []))
  }

  @Test func doesNotShowForAnEmptyDisplay() {
    let empty = CGRect(x: 0, y: 0, width: 0, height: 0)
    #expect(
      !MissionControl.isShowing(windows: [dock(layer: 18, bounds: laptop)], displays: [empty]))
  }

  @Test func doesNotShowWithoutWindows() {
    #expect(!MissionControl.isShowing(windows: [], displays: [laptop]))
  }
}
