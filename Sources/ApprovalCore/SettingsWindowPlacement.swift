import CoreGraphics

public enum SettingsWindowPlacement {
  public static let defaultContentSize = CGSize(width: 820, height: 800)
  public static let minimumContentSize = CGSize(width: 680, height: 480)

  public static func defaultContentSize(fitting available: CGSize) -> CGSize {
    CGSize(
      width: max(minimumContentSize.width, min(defaultContentSize.width, available.width)),
      height: max(minimumContentSize.height, min(defaultContentSize.height, available.height)))
  }

  public static func centeredOrigin(frameSize: CGSize, visibleFrame: CGRect) -> CGPoint {
    let x =
      frameSize.width > visibleFrame.width
      ? visibleFrame.minX : visibleFrame.midX - frameSize.width / 2
    let y =
      frameSize.height > visibleFrame.height
      ? visibleFrame.maxY - frameSize.height : visibleFrame.midY - frameSize.height / 2
    return CGPoint(x: x, y: y)
  }

  public static func isUsable(frame: CGRect, contentSize: CGSize, visibleFrames: [CGRect]) -> Bool {
    contentSize.width >= minimumContentSize.width
      && contentSize.height >= minimumContentSize.height
      && visibleFrames.contains { $0.contains(frame) }
  }
}
