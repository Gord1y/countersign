import SwiftUI

struct HoverCardBody<Content: View>: View {
  let width: CGFloat
  let content: Content

  init(width: CGFloat, @ViewBuilder content: () -> Content) {
    self.width = width
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      content
    }
    .font(PanelTypography.caption)
    .foregroundStyle(.secondary)
    .padding(10)
    .frame(width: width, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    .allowsHitTesting(false)
  }
}

private struct HoverCardModifier<CardContent: View>: ViewModifier {
  let width: CGFloat
  let alignment: Alignment
  let offsetY: CGFloat
  let card: () -> CardContent

  @State private var isHovering = false

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .onHover { isHovering = $0 }
      .overlay(alignment: alignment) {
        if isHovering {
          HoverCardBody(width: width) { card() }
            .offset(y: offsetY)
            .zIndex(1)
        }
      }
  }
}

extension View {
  func hoverCard<CardContent: View>(
    width: CGFloat,
    alignment: Alignment = .topTrailing,
    offsetY: CGFloat = 30,
    @ViewBuilder card: @escaping () -> CardContent
  ) -> some View {
    modifier(HoverCardModifier(width: width, alignment: alignment, offsetY: offsetY, card: card))
  }
}
