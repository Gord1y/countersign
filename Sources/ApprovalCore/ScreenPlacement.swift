import CoreGraphics

public struct ScreenPlacement: Equatable, Sendable {
  public struct Screen: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
      self.frame = frame
      self.visibleFrame = visibleFrame
    }
  }

  public let screenIndex: Int
  public let frame: CGRect

  public static func place(_ window: CGRect, on screens: [Screen]) -> ScreenPlacement? {
    guard let index = screenIndex(for: window, on: screens) else { return nil }
    return ScreenPlacement(
      screenIndex: index, frame: clamp(window, into: screens[index].visibleFrame))
  }

  private static func screenIndex(for window: CGRect, on screens: [Screen]) -> Int? {
    guard !screens.isEmpty else { return nil }
    let centre = CGPoint(x: window.midX, y: window.midY)
    if let holding = screens.firstIndex(where: { $0.frame.contains(centre) }) {
      return holding
    }
    let overlaps = screens.map { overlapArea(of: window, with: $0.frame) }
    guard let largest = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }),
      overlaps[largest] > 0
    else { return 0 }
    return largest
  }

  private static func overlapArea(of window: CGRect, with screen: CGRect) -> CGFloat {
    let overlap = window.intersection(screen)
    guard !overlap.isNull else { return 0 }
    return overlap.width * overlap.height
  }

  private static func clamp(_ window: CGRect, into visibleFrame: CGRect) -> CGRect {
    let width = min(window.width, visibleFrame.width)
    let height = min(window.height, visibleFrame.height)
    return CGRect(
      x: min(max(window.minX, visibleFrame.minX), visibleFrame.maxX - width),
      y: min(max(window.minY, visibleFrame.minY), visibleFrame.maxY - height),
      width: width, height: height)
  }
}
