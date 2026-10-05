import AppKit
import ApprovalCore
import SwiftUI

enum PanelMetrics {
  static let width: CGFloat = 640
  static let padding: CGFloat = 20
  static let sectionSpacing: CGFloat = 14
  static let cornerRadius: CGFloat = 18
}

enum PanelSurface: Sendable {
  case material
  case solid

  var fill: AnyShapeStyle {
    switch self {
    case .material: return AnyShapeStyle(.regularMaterial)
    case .solid: return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    }
  }
}

private struct PanelSurfaceKey: EnvironmentKey {
  static let defaultValue = PanelSurface.material
}

extension EnvironmentValues {
  var panelSurface: PanelSurface {
    get { self[PanelSurfaceKey.self] }
    set { self[PanelSurfaceKey.self] = newValue }
  }
}

@MainActor
@Observable
final class AccentTheme {
  static let shared = AccentTheme()

  var palette = AccentPalette(accent: Settings.defaultAccentColor)
}

@MainActor
enum CountersignPalette {
  static var accent: Color {
    Color(nsColor: NSColor(AccentTheme.shared.palette.fill))
  }

  static var onAccent: Color {
    Color(nsColor: NSColor(AccentTheme.shared.palette.label))
  }

  static var accentText: Color {
    let palette = AccentTheme.shared.palette
    return Color(
      nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
          return NSColor(palette.darkText)
        }
        return NSColor(palette.lightText)
      })
  }

  static func use(_ accentColor: HexColor) {
    let palette = AccentPalette(accent: accentColor)
    guard AccentTheme.shared.palette != palette else { return }
    AccentTheme.shared.palette = palette
  }
}

extension NSColor {
  convenience init(_ color: HexColor) {
    self.init(
      srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
      blue: CGFloat(color.blue) / 255, alpha: 1)
  }
}

extension AppearanceChoice {
  var windowAppearance: NSAppearance? {
    switch self {
    case .system: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }
}

enum PanelTypography {
  static let title = Font.system(size: 17, weight: .semibold)
  static let body = Font.system(size: 13)
  static let secondary = Font.system(size: 12)
  static let caption = Font.system(size: 11, weight: .medium)
  static let code = Font.system(size: 12.5, design: .monospaced)
}

private struct PanelFilledButtonLabel: View {
  let configuration: ButtonStyleConfiguration
  let fill: Color
  let hoverFill: Color
  let foreground: Color
  let font: Font

  @State private var isHovering = false
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(font)
      .foregroundStyle(foreground)
      .frame(height: 30)
      .padding(.horizontal, 14)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isHovering ? hoverFill : fill)
      )
      .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.4))
      .onHover { hovering in isHovering = hovering }
  }
}

private struct PanelLinkButtonLabel: View {
  let configuration: ButtonStyleConfiguration

  @State private var isHovering = false
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(.system(size: 12))
      .foregroundStyle(isHovering ? Color.primary : Color.secondary)
      .frame(height: 30)
      .padding(.horizontal, 14)
      .opacity(configuration.isPressed ? 0.8 : (isEnabled ? 1 : 0.4))
      .onHover { hovering in isHovering = hovering }
  }
}

struct PrimaryButtonStyle: ButtonStyle {
  var fill = CountersignPalette.accent
  var label = CountersignPalette.onAccent

  static let labelCapHeight = NSFont.systemFont(ofSize: 13, weight: .semibold).capHeight

  func makeBody(configuration: Configuration) -> some View {
    PanelFilledButtonLabel(
      configuration: configuration,
      fill: fill,
      hoverFill: fill.opacity(0.85),
      foreground: label,
      font: .system(size: 13, weight: .semibold))
  }
}

struct SecondaryButtonStyle: ButtonStyle {
  static let labelCapHeight = NSFont.systemFont(ofSize: 13, weight: .medium).capHeight

  func makeBody(configuration: Configuration) -> some View {
    PanelFilledButtonLabel(
      configuration: configuration,
      fill: Color.primary.opacity(0.08),
      hoverFill: Color.primary.opacity(0.14),
      foreground: .primary,
      font: .system(size: 13, weight: .medium))
  }
}

struct DestructiveButtonStyle: ButtonStyle {
  static let labelCapHeight = NSFont.systemFont(ofSize: 13, weight: .semibold).capHeight

  func makeBody(configuration: Configuration) -> some View {
    PanelFilledButtonLabel(
      configuration: configuration,
      fill: Color.red.opacity(0.14),
      hoverFill: Color.red.opacity(0.22),
      foreground: .red,
      font: .system(size: 13, weight: .semibold))
  }
}

struct LinkButtonStyle: ButtonStyle {
  static let labelCapHeight = NSFont.systemFont(ofSize: 12).capHeight

  func makeBody(configuration: Configuration) -> some View {
    PanelLinkButtonLabel(configuration: configuration)
  }
}

struct CodeCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.primary.opacity(0.05))
      )
      .overlay(
        PanelBorder(
          shape: RoundedRectangle(cornerRadius: 10, style: .continuous), opacity: 0.08)
      )
  }
}

struct PanelBorder<BorderShape: InsettableShape>: View {
  static var increasedContrastOpacity: Double { 0.5 }

  let shape: BorderShape
  let opacity: Double

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    shape.stroke(
      Color.primary.opacity(contrast == .increased ? Self.increasedContrastOpacity : opacity),
      lineWidth: 1)
  }
}

extension View {
  func panelButtonAccessibility(shortcut: String) -> some View {
    accessibilityHint(PanelAnnouncement.shortcutHint(for: shortcut))
  }

  func panelPrimaryAccessibility(shortcut: String, model: PanelModel) -> some View {
    panelButtonAccessibility(shortcut: shortcut)
      .accessibilityValue(model.isArmed ? "" : PanelAnnouncement.notAvailableYet)
  }
}

struct Chip: View {
  let text: String
  var symbol: String?
  var tint: Color?
  var spokenLabel: String?

  init(
    _ text: String, symbol: String? = nil, tint: Color? = nil, spokenLabel: String? = nil
  ) {
    self.text = text
    self.symbol = symbol
    self.tint = tint
    self.spokenLabel = spokenLabel
  }

  var body: some View {
    HStack(spacing: 4) {
      if let symbol {
        Image(systemName: symbol)
          .accessibilityHidden(true)
      }
      Text(text)
        .lineLimit(1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(spokenLabel ?? text)
    .fixedSize()
    .font(PanelTypography.caption)
    .foregroundStyle(tint ?? Color.primary)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill((tint ?? Color.primary).opacity(0.12)))
  }
}

struct KeyHint: View {
  enum Placement: Sendable {
    case outlined
    case onAccent
    case onDestructive
    case onSecondary
    case link
  }

  let text: String
  let placement: Placement

  init(_ text: String, placement: Placement = .outlined) {
    self.text = text
    self.placement = placement
  }

  private static let outlinedWidth: CGFloat = 20

  var body: some View {
    Text(text)
      .accessibilityHidden(true)
      .font(PanelTypography.caption)
      .monospacedDigit()
      .foregroundStyle(foreground)
      .padding(.horizontal, isBadged ? 6 : 0)
      .padding(.vertical, isBadged ? 2 : 0)
      .frame(width: placement == .outlined ? Self.outlinedWidth : nil)
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .stroke(Color.secondary.opacity(isBadged ? 0.3 : 0), lineWidth: 1)
      )
  }

  private var isBadged: Bool {
    switch placement {
    case .outlined, .link: return true
    case .onAccent, .onDestructive, .onSecondary: return false
    }
  }

  private var foreground: Color {
    switch placement {
    case .outlined: return .secondary
    case .onAccent: return CountersignPalette.onAccent.opacity(0.8)
    case .onDestructive: return .red.opacity(0.8)
    case .onSecondary: return .primary.opacity(0.8)
    case .link: return .secondary
    }
  }
}

private struct KeyHintMidline: AlignmentID {
  static func defaultValue(in context: ViewDimensions) -> CGFloat {
    context[VerticalAlignment.center]
  }
}

extension VerticalAlignment {
  static let keyHintMidline = VerticalAlignment(KeyHintMidline.self)
}

extension View {
  func keyHintTextGuide(capHeight: CGFloat) -> some View {
    alignmentGuide(.keyHintMidline) { dimensions in
      dimensions[VerticalAlignment.firstTextBaseline] - capHeight / 2
    }
  }

  func keyHintGuide() -> some View {
    alignmentGuide(.keyHintMidline) { dimensions in
      dimensions[VerticalAlignment.center]
    }
  }
}

struct AnswerInChatButton: View {
  let model: PanelModel

  var body: some View {
    HStack(alignment: .keyHintMidline, spacing: 6) {
      Button {
        model.finish(.noDecision)
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text(model.escapeKeepsWaiting ? "Later" : "Answer in chat")
            .keyHintTextGuide(capHeight: LinkButtonStyle.labelCapHeight)
          KeyHint("esc", placement: .link)
            .keyHintGuide()
        }
      }
      .buttonStyle(LinkButtonStyle())
      .panelButtonAccessibility(shortcut: "esc")
      .disabled(!model.isArmed)
    }
  }
}

extension View {
  func reportHeight(_ perform: @escaping (CGFloat) -> Void) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear
          .onAppear { perform(proxy.size.height) }
          .onChange(of: proxy.size.height) { _, newValue in perform(newValue) }
      }
    )
  }
}

struct PanelScaffold<Body: View, Footer: View>: View {
  let model: PanelModel
  let availableHeight: CGFloat
  let content: Body
  let footer: Footer

  @State private var bodyHeight: CGFloat = 0
  @State private var footerHeight: CGFloat = 0
  @State private var armProgress: CGFloat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    model: PanelModel,
    availableHeight: CGFloat,
    @ViewBuilder body: () -> Body,
    @ViewBuilder footer: () -> Footer
  ) {
    self.model = model
    self.availableHeight = availableHeight
    self.content = body()
    self.footer = footer()
  }

  private var scrollHeight: CGFloat {
    let footerBudget = max(availableHeight - footerHeight, 0)
    return min(bodyHeight, footerBudget)
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView(.vertical) {
        content
          .padding(PanelMetrics.padding)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .reportHeight { bodyHeight = $0 }
      }
      .frame(minHeight: scrollHeight, maxHeight: scrollHeight)
      .frame(maxHeight: .infinity, alignment: .top)

      footer
        .padding(.horizontal, PanelMetrics.padding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) { armProgressLine }
        .reportHeight { footerHeight = $0 }
    }
    .frame(maxHeight: .infinity, alignment: .top)
    .onChange(of: model.hasStartedArming, initial: true) { _, hasStarted in
      if hasStarted {
        startArmProgressIfNeeded()
      }
    }
  }

  @ViewBuilder
  private var armProgressLine: some View {
    if !model.isArmed {
      Rectangle()
        .fill(CountersignPalette.accentText)
        .frame(height: 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(x: armProgress, y: 1, anchor: .leading)
        .accessibilityHidden(true)
    }
  }

  private func startArmProgressIfNeeded() {
    guard model.armDuration > 0 else { return }
    guard !reduceMotion else {
      armProgress = 1
      return
    }
    armProgress = 0
    withAnimation(.linear(duration: model.armDuration)) {
      armProgress = 1
    }
  }
}

extension View {
  func reportWidth<Key: PreferenceKey>(to key: Key.Type) -> some View where Key.Value == CGFloat {
    background(
      GeometryReader { proxy in
        Color.clear.preference(key: Key.self, value: proxy.size.width)
      }
    )
  }
}
