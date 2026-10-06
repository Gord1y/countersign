import SwiftUI

struct KeyHintFlowLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var origin = CGPoint.zero
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if origin.x > 0, origin.x + size.width > maxWidth {
        origin.x = 0
        origin.y += lineHeight + spacing
        lineHeight = 0
      }
      origin.x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: maxWidth, height: origin.y + lineHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var origin = bounds.origin
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
        origin.x = bounds.minX
        origin.y += lineHeight + spacing
        lineHeight = 0
      }
      subview.place(at: origin, anchor: .topLeading, proposal: .unspecified)
      origin.x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}
