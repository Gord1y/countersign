import ApprovalCore
import SwiftUI

struct WaitingChipView: View {
  let entries: [WaitingEntry]

  @State private var isHovering = false
  @State private var isManuallyClosed = false
  @State private var isOpenedByAction = false

  private var isExpanded: Bool { (isHovering && !isManuallyClosed) || isOpenedByAction }

  var body: some View {
    Button {
      if isExpanded {
        isOpenedByAction = false
        isManuallyClosed = true
      } else {
        isOpenedByAction = true
      }
    } label: {
      Chip(
        "+\(entries.count)", symbol: "clock", tint: CountersignPalette.accentText,
        spokenLabel: "\(entries.count) waiting")
    }
    .buttonStyle(.plain)
    .accessibilityHint(isExpanded ? "Hides the list" : "Shows the list")
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovering = hovering
      if hovering {
        isManuallyClosed = false
      }
    }
    .overlay(alignment: .topTrailing) {
      if isExpanded {
        WaitingListView(entries: entries)
          .offset(y: 30)
          .zIndex(1)
      }
    }
  }
}

private struct WaitingListView: View {
  let entries: [WaitingEntry]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
        WaitingRow(entry: entry)
      }
    }
    .padding(10)
    .frame(width: 300, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      PanelBorder(shape: RoundedRectangle(cornerRadius: 10, style: .continuous), opacity: 0.1)
    )
    .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    .allowsHitTesting(false)
  }
}

private struct WaitingRow: View {
  let entry: WaitingEntry

  var body: some View {
    Group {
      if let summary = entry.summary {
        HStack(spacing: 4) {
          Text(summary.host.displayName)
          dot
          Text(summary.project)
            .lineLimit(1)
            .truncationMode(.tail)
          dot
          Text(summary.tool)
          if let agentLabel = summary.agentLabel {
            dot
            Text(agentLabel)
              .lineLimit(1)
              .truncationMode(.tail)
          }
        }
      } else {
        Text("Unknown request")
      }
    }
    .font(PanelTypography.caption)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }

  private var dot: some View {
    Text("·").foregroundStyle(.tertiary).accessibilityHidden(true)
  }
}
