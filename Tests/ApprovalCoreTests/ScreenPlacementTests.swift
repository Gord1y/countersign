import CoreGraphics
import Testing

@testable import ApprovalCore

@Suite struct ScreenPlacementTests {
  private let laptop = ScreenPlacement.Screen(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
  private let externalOnTheRight = ScreenPlacement.Screen(
    frame: CGRect(x: 1512, y: -200, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1512, y: -200, width: 2560, height: 1415))
  private let externalOnTheLeft = ScreenPlacement.Screen(
    frame: CGRect(x: -2560, y: -200, width: 2560, height: 1440),
    visibleFrame: CGRect(x: -2560, y: -200, width: 2560, height: 1415))

  @Test func keepsAWindowThatFitsTheScreenHoldingItsCentre() {
    let window = CGRect(x: 2000, y: 300, width: 640, height: 500)
    #expect(
      ScreenPlacement.place(window, on: [laptop, externalOnTheRight])
        == ScreenPlacement(screenIndex: 1, frame: window))
  }

  @Test func movesAWindowWhoseScreenIsGoneOntoTheRemainingOneClamped() {
    #expect(
      ScreenPlacement.place(CGRect(x: 2000, y: 300, width: 640, height: 500), on: [laptop])
        == ScreenPlacement(screenIndex: 0, frame: CGRect(x: 872, y: 300, width: 640, height: 500)))
  }

  @Test func followsTheNewOriginsWhenTheSameScreensAreRearranged() {
    #expect(
      ScreenPlacement.place(
        CGRect(x: 2200, y: 600, width: 640, height: 500), on: [laptop, externalOnTheLeft])
        == ScreenPlacement(screenIndex: 0, frame: CGRect(x: 872, y: 444, width: 640, height: 500)))
    #expect(
      ScreenPlacement.place(
        CGRect(x: -1500, y: 300, width: 640, height: 500), on: [laptop, externalOnTheLeft])
        == ScreenPlacement(
          screenIndex: 1, frame: CGRect(x: -1500, y: 300, width: 640, height: 500)))
  }

  @Test func picksTheLargerOverlapForAWindowStraddlingTwoScreensWithItsCentreOnNeither() {
    let raised = ScreenPlacement.Screen(
      frame: CGRect(x: 1512, y: 400, width: 2560, height: 1440),
      visibleFrame: CGRect(x: 1512, y: 400, width: 2560, height: 1415))
    #expect(
      ScreenPlacement.place(CGRect(x: 1450, y: 0, width: 640, height: 700), on: [laptop, raised])
        == ScreenPlacement(
          screenIndex: 1, frame: CGRect(x: 1512, y: 400, width: 640, height: 700)))
    #expect(
      ScreenPlacement.place(CGRect(x: 1300, y: 0, width: 500, height: 700), on: [raised, laptop])
        == ScreenPlacement(screenIndex: 1, frame: CGRect(x: 1012, y: 0, width: 500, height: 700)))
  }

  @Test func clampsAFrameLargerThanTheVisibleFrame() {
    #expect(
      ScreenPlacement.place(CGRect(x: -100, y: -50, width: 2000, height: 1200), on: [laptop])
        == ScreenPlacement(screenIndex: 0, frame: CGRect(x: 0, y: 0, width: 1512, height: 944)))
  }

  @Test func clampsAFrameUnderTheMenuBarDownIntoTheVisibleFrame() {
    #expect(
      ScreenPlacement.place(CGRect(x: 400, y: 700, width: 640, height: 280), on: [laptop])
        == ScreenPlacement(screenIndex: 0, frame: CGRect(x: 400, y: 664, width: 640, height: 280)))
  }

  @Test func fallsBackToTheFirstScreenWhenTheWindowTouchesNone() {
    #expect(
      ScreenPlacement.place(
        CGRect(x: 9000, y: 9000, width: 640, height: 500), on: [externalOnTheRight, laptop])
        == ScreenPlacement(
          screenIndex: 0, frame: CGRect(x: 3432, y: 715, width: 640, height: 500)))
  }

  @Test func placesNothingWhenThereIsNoScreen() {
    #expect(ScreenPlacement.place(CGRect(x: 0, y: 0, width: 640, height: 500), on: []) == nil)
  }
}
