import AppKit
import ApprovalCore

enum MenuBarIcon {
  static let canvasSize: CGFloat = 18

  private static let nibOrigin = CGPoint(x: 6.45, y: 7.9)
  private static let nibRotation: CGFloat = 45 * .pi / 180
  private static let nibScale: CGFloat = 0.98
  private static let nibOutlineWidth: CGFloat = 1.25
  private static let nibDetailWidth: CGFloat = 1.1

  private static let pauseBarWidth: CGFloat = 1.98
  private static let pauseBarHeight: CGFloat = 5.94
  private static let pauseBarCornerRadius: CGFloat = 0.79
  private static let pauseBarTop: CGFloat = 11.33
  private static let pauseBarLeftX: CGFloat = 11.66
  private static let pauseBarRightX: CGFloat = 14.96

  private static let moonCenter = CGPoint(x: 14.3, y: 14.3)
  private static let moonRadius: CGFloat = 3.3
  private static let moonKnockoutCenter = CGPoint(x: 16.28, y: 12.72)
  private static let moonKnockoutRadius: CGFloat = 2.64

  static func image(for icon: CompanionIcon) -> NSImage {
    let canvas = CGSize(width: canvasSize, height: canvasSize)
    let image = NSImage(size: canvas, flipped: false) { _ in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      draw(icon, in: context, color: NSColor.black.cgColor)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = icon.accessibilityLabel
    return image
  }

  static func draw(_ icon: CompanionIcon, in context: CGContext, color: CGColor) {
    context.saveGState()
    context.translateBy(x: 0, y: canvasSize)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(color)
    context.addPath(nibPath())
    context.fillPath()
    switch icon {
    case .active:
      break
    case .paused:
      for bar in pauseBarPaths() {
        context.addPath(bar)
      }
      context.fillPath()
    case .quiet:
      let (outer, knockout) = moonPaths()
      context.addPath(outer)
      context.fillPath()
      context.setBlendMode(.destinationOut)
      context.addPath(knockout)
      context.fillPath()
      context.setBlendMode(.normal)
    }
    context.restoreGState()
  }

  private static var nibTransform: CGAffineTransform {
    CGAffineTransform(translationX: nibOrigin.x, y: nibOrigin.y)
      .rotated(by: nibRotation)
      .scaledBy(x: nibScale, y: nibScale)
  }

  private static func strokedPath(
    _ path: CGPath, width: CGFloat
  ) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
  }

  private static func nibOutlinePath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 8))
    path.addCurve(
      to: CGPoint(x: 3.6, y: -0.6), control1: CGPoint(x: 0.9, y: 5.6),
      control2: CGPoint(x: 3.6, y: 2.6))
    path.addLine(to: CGPoint(x: 3.6, y: -2.6))
    path.addLine(to: CGPoint(x: 2.6, y: -3.2))
    path.addLine(to: CGPoint(x: 2.6, y: -7.5))
    path.addLine(to: CGPoint(x: -2.6, y: -7.5))
    path.addLine(to: CGPoint(x: -2.6, y: -3.2))
    path.addLine(to: CGPoint(x: -3.6, y: -2.6))
    path.addLine(to: CGPoint(x: -3.6, y: -0.6))
    path.addCurve(
      to: CGPoint(x: 0, y: 8), control1: CGPoint(x: -3.6, y: 2.6),
      control2: CGPoint(x: -0.9, y: 5.6))
    path.closeSubpath()
    return path
  }

  private static func nibSlitPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 1.6))
    path.addLine(to: CGPoint(x: 0, y: 6.2))
    return path
  }

  private static func nibCollarPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -2.6, y: -3.2))
    path.addLine(to: CGPoint(x: 2.6, y: -3.2))
    return path
  }

  private static func nibBreatherHolePath() -> CGPath {
    let radius: CGFloat = 1.1
    let center = CGPoint(x: 0, y: 0.6)
    return CGPath(
      ellipseIn: CGRect(
        x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2),
      transform: nil)
  }

  private static func nibPath() -> CGPath {
    let path = CGMutablePath()
    path.addPath(strokedPath(nibOutlinePath(), width: nibOutlineWidth))
    path.addPath(strokedPath(nibSlitPath(), width: nibDetailWidth))
    path.addPath(strokedPath(nibCollarPath(), width: nibDetailWidth))
    path.addPath(nibBreatherHolePath())
    var transform = nibTransform
    return path.copy(using: &transform) ?? path
  }

  private static func pauseBarPaths() -> [CGPath] {
    let corner = pauseBarCornerRadius
    return [pauseBarLeftX, pauseBarRightX].map { x in
      CGPath(
        roundedRect: CGRect(x: x, y: pauseBarTop, width: pauseBarWidth, height: pauseBarHeight),
        cornerWidth: corner, cornerHeight: corner, transform: nil)
    }
  }

  private static func moonPaths() -> (outer: CGPath, knockout: CGPath) {
    let outer = CGPath(
      ellipseIn: CGRect(
        x: moonCenter.x - moonRadius, y: moonCenter.y - moonRadius, width: moonRadius * 2,
        height: moonRadius * 2), transform: nil)
    let knockout = CGPath(
      ellipseIn: CGRect(
        x: moonKnockoutCenter.x - moonKnockoutRadius, y: moonKnockoutCenter.y - moonKnockoutRadius,
        width: moonKnockoutRadius * 2, height: moonKnockoutRadius * 2), transform: nil)
    return (outer, knockout)
  }
}
