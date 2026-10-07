import CoreGraphics
import Testing

@testable import ApprovalCore

@Suite struct SettingsWindowPlacementTests {
  private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
  private let external = CGRect(x: 1512, y: -200, width: 2560, height: 1415)

  @Test func sizesMatchTheWindowsDefaultAndMinimum() {
    #expect(SettingsWindowPlacement.defaultContentSize == CGSize(width: 820, height: 800))
    #expect(SettingsWindowPlacement.minimumContentSize == CGSize(width: 680, height: 480))
  }

  @Test func keepsTheDefaultSizeWhenTheScreenHasRoomForIt() {
    #expect(
      SettingsWindowPlacement.defaultContentSize(fitting: CGSize(width: 1512, height: 916))
        == CGSize(width: 820, height: 800))
  }

  @Test func shrinksTheDefaultSizeToASmallScreen() {
    #expect(
      SettingsWindowPlacement.defaultContentSize(fitting: CGSize(width: 1024, height: 580))
        == CGSize(width: 820, height: 580))
    #expect(
      SettingsWindowPlacement.defaultContentSize(fitting: CGSize(width: 750, height: 550))
        == CGSize(width: 750, height: 550))
  }

  @Test func neverShrinksTheDefaultSizeBelowTheMinimum() {
    #expect(
      SettingsWindowPlacement.defaultContentSize(fitting: CGSize(width: 400, height: 300))
        == CGSize(width: 680, height: 480))
  }

  @Test func acceptsAFrameInsideOneScreen() {
    #expect(
      SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 400, y: 100, width: 820, height: 818),
        contentSize: CGSize(width: 820, height: 790), visibleFrames: [laptop, external]))
    #expect(
      SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 1600, y: -100, width: 1280, height: 828),
        contentSize: CGSize(width: 1280, height: 800), visibleFrames: [laptop, external]))
  }

  @Test func acceptsAFrameThatFillsAScreenExactly() {
    #expect(
      SettingsWindowPlacement.isUsable(
        frame: laptop, contentSize: CGSize(width: 1512, height: 916), visibleFrames: [laptop]))
  }

  @Test func acceptsTheMinimumSize() {
    #expect(
      SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 100, y: 100, width: 680, height: 508),
        contentSize: CGSize(width: 680, height: 480), visibleFrames: [laptop]))
  }

  @Test func rejectsAFrameNarrowerOrShorterThanTheMinimum() {
    #expect(
      !SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 100, y: 100, width: 679, height: 818),
        contentSize: CGSize(width: 679, height: 790), visibleFrames: [laptop]))
    #expect(
      !SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 100, y: 100, width: 820, height: 507),
        contentSize: CGSize(width: 820, height: 479), visibleFrames: [laptop]))
  }

  @Test func rejectsAFrameOnAScreenThatIsGone() {
    #expect(
      !SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 1600, y: -100, width: 820, height: 818),
        contentSize: CGSize(width: 820, height: 790), visibleFrames: [laptop]))
  }

  @Test func rejectsAFramePartlyOffEveryScreen() {
    #expect(
      !SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 1200, y: 100, width: 820, height: 818),
        contentSize: CGSize(width: 820, height: 790), visibleFrames: [laptop, external]))
    #expect(
      !SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 400, y: 400, width: 820, height: 818),
        contentSize: CGSize(width: 820, height: 790), visibleFrames: [laptop]))
  }

  @Test func centersAFrameOnBothAxes() {
    #expect(
      SettingsWindowPlacement.centeredOrigin(
        frameSize: CGSize(width: 400, height: 300),
        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875))
        == CGPoint(x: 520, y: 312.5))
  }

  @Test func pinsAFrameTallerThanTheVisibleFrameToItsTop() {
    #expect(
      SettingsWindowPlacement.centeredOrigin(
        frameSize: CGSize(width: 400, height: 900),
        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 800))
        == CGPoint(x: 520, y: -75))
  }

  @Test func pinsAFrameWiderThanTheVisibleFrameToItsLeft() {
    #expect(
      SettingsWindowPlacement.centeredOrigin(
        frameSize: CGSize(width: 1600, height: 300),
        visibleFrame: CGRect(x: 10, y: 25, width: 1440, height: 875))
        == CGPoint(x: 10, y: 312.5))
  }

  @Test func rejectsAnyFrameWhenThereIsNoScreen() {
    #expect(
      !SettingsWindowPlacement.isUsable(
        frame: CGRect(x: 400, y: 100, width: 820, height: 818),
        contentSize: CGSize(width: 820, height: 790), visibleFrames: []))
  }
}
