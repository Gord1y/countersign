import CoreGraphics

public enum MissionControl {
  public struct Window: Equatable, Sendable {
    public let ownerName: String
    public let layer: Int
    public let bounds: CGRect

    public init(ownerName: String, layer: Int, bounds: CGRect) {
      self.ownerName = ownerName
      self.layer = layer
      self.bounds = bounds
    }
  }

  public static let overlayOwnerName = "Dock"
  public static let overlayLayer = 18
  public static let minimumDisplayCoverage: CGFloat = 0.9

  public static func isShowing(windows: [Window], displays: [CGRect]) -> Bool {
    windows.contains { window in
      window.ownerName == overlayOwnerName && window.layer == overlayLayer
        && displays.contains { covers(window.bounds, display: $0) }
    }
  }

  private static func covers(_ bounds: CGRect, display: CGRect) -> Bool {
    let displayArea = display.width * display.height
    guard displayArea > 0 else { return false }
    let overlap = bounds.intersection(display)
    guard !overlap.isNull else { return false }
    return overlap.width * overlap.height >= displayArea * minimumDisplayCoverage
  }
}
