import AppKit
import ApprovalCore
import SwiftUI

struct PanelRootView: View {
  let model: PanelModel
  let width: CGFloat
  let maxHeight: CGFloat

  @State private var headerHeight: CGFloat = 0
  @State private var isChainCardHovering = false
  @State private var dropdownFloor: CGFloat?
  @Environment(\.panelSurface) private var surface

  private var request: ApprovalRequest { model.request }
  private var host: ApprovalCore.Host { request.host }

  private var availableHeight: CGFloat {
    max(maxHeight - headerHeight, 0)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
        .reportHeight { headerHeight = $0 }
        .zIndex(1)
      content
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(minHeight: dropdownFloor.map { min($0, maxHeight) }, alignment: .top)
    .frame(width: width)
    .frame(maxHeight: maxHeight, alignment: .top)
    .overlayPreferenceValue(PanelDropdownAnchorKey.self) { anchors in
      dropdownLayer(anchors: anchors)
    }
    .background(surface.fill)
    .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
    )
    .reportHeight { model.onPreferredHeightChange?(min($0, maxHeight)) }
    .onAppear {
      if model.onSnooze != nil, model.dropdown.takeRequest(for: .snooze) {
        toggleSnoozeDropdown()
      }
    }
  }

  private func dropdownLayer(anchors: [PanelDropdownID: Anchor<CGRect>]) -> some View {
    GeometryReader { proxy in
      if let menu = model.dropdown.menu, let anchor = anchors[menu.id] {
        PanelDropdownLayer(
          state: model.dropdown, menu: menu, anchorFrame: proxy[anchor],
          containerSize: proxy.size, isEnabled: model.isArmed
        ) { floor in
          dropdownFloor = floor
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      CountersignMark()
        .frame(width: 20, height: 20)

      Text(host.displayName)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(1)
        .fixedSize()

      chevron

      Text(request.projectName)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(
          minWidth: min(Self.naturalWidth(of: request.projectName), Self.projectNameFloor),
          alignment: .leading
        )
        .layoutPriority(1)

      if model.isTestPanel {
        Chip("Test")
          .hoverCard(width: 260, alignment: .topLeading) {
            Text(Self.testPanelText)
          }
      }

      if model.chatTrackingDrift != nil {
        chatTrackingWarningIcon
      }

      if let chain = resolvedChain {
        if chain.count > 1 {
          chevron
          Text("…")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize()
            .onHover { isChainCardHovering = $0 }
        }
        chevron
        askingLabel(for: chain)
      } else if let agentType = request.agentType {
        Chip("subagent · \(agentType)", symbol: "person.2")
      }
      if let modeDisplay = PermissionModeDisplay.forMode(request.permissionMode, host: host) {
        Chip(modeDisplay.label, symbol: "shield")
          .hoverCard(width: 280) {
            Text(modeDisplay.tooltip)
          }
      }

      Spacer()

      if model.onSnooze != nil {
        snoozeButton
      }

      if !model.waitingEntries.isEmpty {
        WaitingChipView(entries: model.waitingEntries)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if isChainCardHovering, let chain = resolvedChain {
        HoverCardBody(width: 360) { chainCardRows(chain) }
          .offset(y: 22)
          .zIndex(1)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .background(Color.primary.opacity(0.03))
  }

  private var chevron: some View {
    Image(systemName: "chevron.right")
      .font(.system(size: 10))
      .foregroundStyle(.secondary)
  }

  private static let testPanelText =
    "A test panel with your settings. Nothing you choose here reaches an agent."

  private static let chatTrackingWarningTriangle = Color(red: 0.918, green: 0.702, blue: 0.031)
  private static let chatTrackingWarningMark = Color(red: 0.098, green: 0.098, blue: 0.098)
  private static let chatTrackingWarningText =
    "Countersign can't follow this chat, so answering there won't close this panel. "
    + "Answer here, or press Esc."

  private var chatTrackingWarningIcon: some View {
    Image(systemName: "exclamationmark.triangle.fill")
      .symbolRenderingMode(.palette)
      .foregroundStyle(Self.chatTrackingWarningMark, Self.chatTrackingWarningTriangle)
      .font(.system(size: 13, weight: .semibold))
      .fixedSize()
      .accessibilityLabel(Self.chatTrackingWarningText)
      .hoverCard(width: 260, alignment: .topLeading, offsetY: 22) {
        Text(Self.chatTrackingWarningText)
      }
  }

  private static let projectNameFloor: CGFloat = 80
  private static let projectNameFont = NSFont.systemFont(ofSize: 13, weight: .medium)

  private static func naturalWidth(of text: String) -> CGFloat {
    (text as NSString).size(withAttributes: [.font: projectNameFont]).width
  }

  private var resolvedChain: [SubagentChainLink]? {
    guard let chain = model.subagentChain, !chain.isEmpty else { return nil }
    return chain
  }

  private func askingLabel(for chain: [SubagentChainLink]) -> some View {
    let link = chain[chain.count - 1]
    let label = link.description.isEmpty ? link.agentType : link.description
    return Text(label)
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .truncationMode(.tail)
      .frame(minWidth: 60, alignment: .leading)
      .onHover { isChainCardHovering = $0 }
  }

  private func chainCardRows(_ chain: [SubagentChainLink]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(chain.enumerated()), id: \.offset) { index, link in
        HStack(alignment: .top, spacing: 6) {
          Text("\(index + 1)")
            .frame(width: 14, alignment: .trailing)
          Text("\(link.agentType) · \(link.description)")
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var snoozeButton: some View {
    Button(action: toggleSnoozeDropdown) {
      Image(systemName: "moon.zzz")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(3)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .fixedSize()
    .disabled(!model.isArmed)
    .panelDropdownAnchor(.snooze)
    .hoverCard(width: 60) {
      Text("Snooze")
    }
  }

  private func toggleSnoozeDropdown() {
    let presets = model.snoozeMinutes
    let rows = presets.enumerated().map { index, minutes in
      PanelDropdownRow(title: SnoozeTitle.describe(minutes: minutes, isFirst: index == 0))
    }
    let menu = PanelDropdownMenu(id: .snooze, direction: .down, rows: rows) { [model] row in
      guard presets.indices.contains(row) else { return }
      model.snooze(TimeInterval(presets[row] * 60))
    }
    model.dropdown.toggle(menu)
  }

  @ViewBuilder
  private var content: some View {
    switch request.kind {
    case .permission(let prompt):
      PermissionView(model: model, prompt: prompt, availableHeight: availableHeight)
    case .questions(let questions):
      QuestionView(model: model, questions: questions, availableHeight: availableHeight)
    case .plan(let plan):
      PlanView(model: model, plan: plan, availableHeight: availableHeight)
    }
  }
}
