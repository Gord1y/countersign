import ApprovalCore
import SwiftUI

enum PanelDropdownID: String, Sendable, Hashable {
  case approve
  case snooze
  case mode
}

enum PanelDropdownDirection: Sendable {
  case up
  case down
}

struct PanelDropdownRow: Sendable, Equatable {
  let title: String
  var detail: String?
  var isChecked = false
}

struct PanelDropdownMenu {
  let id: PanelDropdownID
  let direction: PanelDropdownDirection
  let rows: [PanelDropdownRow]
  var startRow = 0
  let onPick: @MainActor (Int) -> Void

  var showsCheckmarks: Bool {
    rows.contains { $0.isChecked }
  }
}

@MainActor
@Observable
final class PanelDropdownState {
  private(set) var menu: PanelDropdownMenu?
  private(set) var navigation = DropdownNavigation(rowCount: 0)
  private var requestedOnAppear: PanelDropdownID?

  init(requestedOnAppear: PanelDropdownID? = nil) {
    self.requestedOnAppear = requestedOnAppear
  }

  var isOpen: Bool { menu != nil }

  var keyHandler: PanelKeyHandler {
    PanelKeyHandler(
      uses: { [weak self] key in self?.uses(key) == true },
      perform: { [weak self] key in self?.perform(key) })
  }

  func toggle(_ newMenu: PanelDropdownMenu) {
    guard menu?.id != newMenu.id else {
      close()
      return
    }
    menu = newMenu
    navigation = DropdownNavigation(rowCount: newMenu.rows.count, highlighting: newMenu.startRow)
  }

  func close() {
    menu = nil
  }

  func highlight(_ row: Int) {
    navigation.highlight(row)
  }

  func pick(_ row: Int) {
    guard let menu, menu.rows.indices.contains(row) else { return }
    close()
    menu.onPick(row)
  }

  func takeRequest(for id: PanelDropdownID) -> Bool {
    guard requestedOnAppear == id else { return false }
    requestedOnAppear = nil
    return true
  }

  private func uses(_ key: PanelKey) -> Bool {
    switch key {
    case .up, .down, .primary: return true
    case .digit(let digit): return navigation.row(forDigit: digit) != nil
    case .left, .right, .secondary, .alternate: return false
    }
  }

  private func perform(_ key: PanelKey) {
    switch key {
    case .up:
      navigation.moveUp()
    case .down:
      navigation.moveDown()
    case .primary:
      pick(navigation.highlightedRow)
    case .digit(let digit):
      if let row = navigation.row(forDigit: digit) {
        pick(row)
      }
    case .left, .right, .secondary, .alternate:
      break
    }
  }
}

struct PanelDropdownAnchorKey: PreferenceKey {
  static var defaultValue: [PanelDropdownID: Anchor<CGRect>] { [:] }

  static func reduce(
    value: inout [PanelDropdownID: Anchor<CGRect>],
    nextValue: () -> [PanelDropdownID: Anchor<CGRect>]
  ) {
    value.merge(nextValue()) { _, next in next }
  }
}

extension View {
  func panelDropdownAnchor(_ id: PanelDropdownID) -> some View {
    anchorPreference(key: PanelDropdownAnchorKey.self, value: .bounds) { [id: $0] }
  }
}

struct PanelDropdownLayer: View {
  let state: PanelDropdownState
  let menu: PanelDropdownMenu
  let anchorFrame: CGRect
  let containerSize: CGSize
  let isEnabled: Bool
  let onFloorChange: (CGFloat?) -> Void

  @State private var cardHeight: CGFloat = 0

  private static let gap: CGFloat = 6
  private static let margin: CGFloat = 8
  private static let minCardWidth: CGFloat = 200

  private var trailingInset: CGFloat {
    max(containerSize.width - anchorFrame.maxX, Self.margin)
  }

  private var maxCardWidth: CGFloat {
    max(containerSize.width - trailingInset - Self.margin, Self.minCardWidth)
  }

  private var verticalInset: CGFloat {
    switch menu.direction {
    case .up: return containerSize.height - anchorFrame.minY + Self.gap
    case .down: return anchorFrame.maxY + Self.gap
    }
  }

  private var floor: CGFloat {
    switch menu.direction {
    case .up:
      return cardHeight + Self.gap + Self.margin + (containerSize.height - anchorFrame.minY)
    case .down:
      return anchorFrame.maxY + Self.gap + cardHeight + Self.margin
    }
  }

  var body: some View {
    ZStack(alignment: menu.direction == .up ? .bottomTrailing : .topTrailing) {
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture { state.close() }
      PanelDropdownWidth(minWidth: Self.minCardWidth, maxWidth: maxCardWidth) {
        PanelDropdownCard(state: state, menu: menu, isEnabled: isEnabled)
      }
      .reportHeight { cardHeight = $0 }
      .padding(.trailing, trailingInset)
      .padding(menu.direction == .up ? .bottom : .top, verticalInset)
    }
    .frame(width: containerSize.width, height: containerSize.height)
    .onChange(of: floor, initial: true) { _, newFloor in onFloorChange(newFloor) }
    .onDisappear { onFloorChange(nil) }
  }
}

private struct PanelDropdownWidth: Layout {
  let minWidth: CGFloat
  let maxWidth: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let card = subviews.first else { return .zero }
    let width = cardWidth(card)
    let height = card.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews.first?.place(
      at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
  }

  private func cardWidth(_ card: LayoutSubview) -> CGFloat {
    min(max(card.sizeThatFits(.unspecified).width, minWidth), maxWidth)
  }
}

private struct PanelDropdownCard: View {
  let state: PanelDropdownState
  let menu: PanelDropdownMenu
  let isEnabled: Bool

  @Environment(\.panelSurface) private var surface

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(menu.rows.enumerated()), id: \.offset) { index, row in
        PanelDropdownRowView(
          row: row, index: index, showsCheckmark: menu.showsCheckmarks,
          isHighlighted: state.navigation.highlightedRow == index,
          onHover: { state.highlight(index) },
          onPick: { state.pick(index) })
      }
    }
    .padding(5)
    .background(
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(surface.fill)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.primary.opacity(0.04))
      }
    )
    .overlay(
      PanelBorder(shape: RoundedRectangle(cornerRadius: 10, style: .continuous), opacity: 0.12)
    )
    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    .disabled(!isEnabled)
  }
}

private struct PanelDropdownRowView: View {
  let row: PanelDropdownRow
  let index: Int
  let showsCheckmark: Bool
  let isHighlighted: Bool
  let onHover: () -> Void
  let onPick: () -> Void

  var body: some View {
    Button(action: onPick) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if showsCheckmark {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CountersignPalette.accentText)
            .opacity(row.isChecked ? 1 : 0)
            .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(row.title)
            .font(PanelTypography.body)
            .fixedSize(horizontal: false, vertical: true)
          if let detail = row.detail {
            Text(detail)
              .font(PanelTypography.secondary)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 16)
        if index < DropdownNavigation.digitLimit {
          KeyHint("\(index + 1)")
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(isHighlighted ? CountersignPalette.accentText.opacity(0.16) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    .accessibilityValue(showsCheckmark && row.isChecked ? "Current" : "")
    .accessibilityHint(
      index < DropdownNavigation.digitLimit
        ? PanelAnnouncement.shortcutHint(for: "\(index + 1)") : ""
    )
    .onHover { hovering in
      if hovering {
        onHover()
      }
    }
  }
}
