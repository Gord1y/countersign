import SwiftUI

struct CountersignMark: View {
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    Canvas { context, size in
      CountersignMarkDrawing(side: min(size.width, size.height), displayScale: displayScale)
        .draw(in: context)
    }
  }
}

private struct MarkCurve {
  let control1: CGPoint
  let control2: CGPoint
  let end: CGPoint
}

private struct CountersignMarkDrawing {
  private static let designTile = CGRect(x: 100, y: 100, width: 824, height: 824)
  private static let designImageSide: CGFloat = 1024
  private static let tileCornerRatio: CGFloat = 0.2237
  private static let tileTop = Color(red: 0.298, green: 0.275, blue: 0.259)
  private static let tileBottom = Color(red: 0.157, green: 0.141, blue: 0.129)
  private static let nibFace = Color(red: 0.957, green: 0.937, blue: 0.910)
  private static let nibInk = Color(red: 0.118, green: 0.106, blue: 0.098)
  private static let signatureInk = Color(red: 0.902, green: 0.690, blue: 0.290)
  private static let signatureTip = CGPoint(x: 500, y: 640)
  private static let signaturePoints = [
    CGPoint(x: 256, y: 690), CGPoint(x: 314, y: 574), CGPoint(x: 370, y: 696),
    CGPoint(x: 436, y: 680), signatureTip,
  ]
  private static let signatureWidth: CGFloat = 68
  private static let penFocus = CGPoint(x: 531, y: 502)
  private static let penShift = CGSize(width: -20, height: 8)
  private static let penEnlargement: CGFloat = 1.12
  private static let nibLength: CGFloat = 390
  private static let nibHalfWidth: CGFloat = 112
  private static let nibAngle: CGFloat = -135 * .pi / 180
  private static let slitWidth: CGFloat = 20
  private static let breatherRadius: CGFloat = 28
  private static let nibRightSide = [
    MarkCurve(
      control1: CGPoint(x: 0.16, y: 0.16), control2: CGPoint(x: 1, y: 0.34),
      end: CGPoint(x: 1, y: 0.62)),
    MarkCurve(
      control1: CGPoint(x: 1, y: 0.70), control2: CGPoint(x: 0.84, y: 0.72),
      end: CGPoint(x: 0.78, y: 0.76)),
    MarkCurve(
      control1: CGPoint(x: 0.78, y: 0.84), control2: CGPoint(x: 0.78, y: 0.92),
      end: CGPoint(x: 0.78, y: 1)),
    MarkCurve(
      control1: CGPoint(x: 0.36, y: 1.05), control2: CGPoint(x: -0.36, y: 1.05),
      end: CGPoint(x: -0.78, y: 1)),
  ]

  let side: CGFloat
  let displayScale: CGFloat

  private var unit: CGFloat { side / Self.designTile.width }

  private var designToView: CGAffineTransform {
    CGAffineTransform(scaleX: unit, y: unit)
      .translatedBy(x: -Self.designTile.minX, y: -Self.designTile.minY)
  }

  private var penToView: CGAffineTransform {
    CGAffineTransform(
      translationX: Self.penFocus.x + Self.penShift.width,
      y: Self.penFocus.y + Self.penShift.height
    )
    .scaledBy(x: Self.penEnlargement, y: Self.penEnlargement)
    .translatedBy(x: -Self.penFocus.x, y: -Self.penFocus.y)
    .concatenating(designToView)
  }

  private var nibToView: CGAffineTransform {
    CGAffineTransform(translationX: Self.signatureTip.x, y: Self.signatureTip.y)
      .rotated(by: Self.nibAngle)
      .concatenating(penToView)
  }

  private var smallSizeBoost: CGFloat {
    let iconPixels = side * displayScale * Self.designImageSide / Self.designTile.width
    return 1 + 0.18 * max(0, log2(128 / iconPixels))
  }

  func draw(in context: GraphicsContext) {
    drawTile(in: context)
    drawPen(in: context)
  }

  private func drawTile(in context: GraphicsContext) {
    let tile = RoundedRectangle(cornerRadius: side * Self.tileCornerRatio, style: .continuous)
      .path(in: CGRect(x: 0, y: 0, width: side, height: side))
    let top = CGPoint(x: 0, y: Self.designTile.minY).applying(designToView)
    let bottom = CGPoint(x: 0, y: Self.designTile.maxY).applying(designToView)
    context.fill(
      tile,
      with: .linearGradient(
        Gradient(colors: [Self.tileTop, Self.tileBottom]), startPoint: top, endPoint: bottom))

    var insideTile = context
    insideTile.clip(to: tile)
    insideTile.fill(
      tile,
      with: .radialGradient(
        Gradient(colors: [.white.opacity(0.14), .white.opacity(0)]),
        center: CGPoint(x: Self.designTile.midX, y: Self.designTile.minY + 40)
          .applying(designToView),
        startRadius: 0, endRadius: Self.designTile.width * 0.7 * unit))
    insideTile.stroke(
      tile,
      with: .linearGradient(
        Gradient(stops: [
          Gradient.Stop(color: .white.opacity(0.30), location: 0),
          Gradient.Stop(color: .white.opacity(0.04), location: 0.45),
          Gradient.Stop(color: .black.opacity(0), location: 0.7),
          Gradient.Stop(color: .black.opacity(0.22), location: 1),
        ]), startPoint: top, endPoint: bottom),
      lineWidth: 10 * unit)
  }

  private func drawPen(in context: GraphicsContext) {
    let penScale = Self.penEnlargement * unit
    context.stroke(
      Self.smoothPath(through: Self.signaturePoints).applying(penToView),
      with: .color(Self.signatureInk),
      style: roundStroke(width: Self.signatureWidth * smallSizeBoost * penScale))

    let nib = Self.nibOutline().applying(nibToView)
    context.drawLayer { layer in
      layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 24 * unit, x: 0, y: 10 * unit))
      layer.fill(nib, with: .color(Self.nibFace))
    }

    var onNib = context
    onNib.clip(to: nib)
    let shadedHalf = CGRect(
      x: -2 * Self.nibHalfWidth, y: -20, width: 2 * Self.nibHalfWidth, height: 1.2 * Self.nibLength)
    onNib.fill(Path(shadedHalf).applying(nibToView), with: .color(.black.opacity(0.13)))

    let breather = CGPoint(x: 0, y: 0.52 * Self.nibLength)
    var slit = Path()
    slit.move(to: CGPoint(x: 0, y: 4))
    slit.addLine(to: breather)
    onNib.stroke(
      slit.applying(nibToView), with: .color(Self.nibInk),
      style: roundStroke(width: Self.slitWidth * smallSizeBoost * penScale))

    let holeRadius = Self.breatherRadius * smallSizeBoost
    let hole = CGRect(
      x: breather.x - holeRadius, y: breather.y - holeRadius, width: 2 * holeRadius,
      height: 2 * holeRadius)
    onNib.fill(Path(ellipseIn: hole).applying(nibToView), with: .color(Self.nibInk))
  }

  private func roundStroke(width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
  }

  private static func smoothPath(through points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for index in 0..<(points.count - 1) {
      let previous = points[max(index - 1, 0)]
      let start = points[index]
      let end = points[index + 1]
      let next = points[min(index + 2, points.count - 1)]
      path.addCurve(
        to: end,
        control1: CGPoint(
          x: start.x + (end.x - previous.x) / 6, y: start.y + (end.y - previous.y) / 6),
        control2: CGPoint(x: end.x - (next.x - start.x) / 6, y: end.y - (next.y - start.y) / 6))
    }
    return path
  }

  private static func nibOutline() -> Path {
    let mirror = CGAffineTransform(scaleX: -1, y: 1)
    let leftSide = (0..<(nibRightSide.count - 1)).reversed().map { index in
      let start = index == 0 ? CGPoint.zero : nibRightSide[index - 1].end
      return MarkCurve(
        control1: nibRightSide[index].control2.applying(mirror),
        control2: nibRightSide[index].control1.applying(mirror), end: start.applying(mirror))
    }
    let size = CGAffineTransform(scaleX: nibHalfWidth, y: nibLength)
    var path = Path()
    path.move(to: .zero)
    for curve in nibRightSide + leftSide {
      path.addCurve(
        to: curve.end.applying(size), control1: curve.control1.applying(size),
        control2: curve.control2.applying(size))
    }
    path.closeSubpath()
    return path
  }
}
