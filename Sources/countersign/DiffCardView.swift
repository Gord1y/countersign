import ApprovalCore
import SwiftUI

enum GapPosition: Sendable, Equatable {
  case start
  case middle
  case end
}

struct GapRevealState: Sendable, Equatable {
  var fromTop: Int
  var fromBottom: Int

  static let zero = GapRevealState(fromTop: 0, fromBottom: 0)

  static func reveal(current: GapRevealState, total: Int, position: GapPosition)
    -> GapRevealState
  {
    let remaining = total - current.fromTop - current.fromBottom
    guard remaining > 0 else { return current }
    let amount = min(30, remaining)
    switch position {
    case .start:
      return GapRevealState(fromTop: current.fromTop, fromBottom: current.fromBottom + amount)
    case .end:
      return GapRevealState(fromTop: current.fromTop + amount, fromBottom: current.fromBottom)
    case .middle:
      let topAdd = min(15, amount)
      let bottomAdd = amount - topAdd
      return GapRevealState(
        fromTop: current.fromTop + topAdd, fromBottom: current.fromBottom + bottomAdd)
    }
  }
}

private func diffCardBackground() -> some View {
  RoundedRectangle(cornerRadius: 10, style: .continuous)
    .fill(Color.primary.opacity(0.03))
}

private func diffCardStroke() -> some View {
  RoundedRectangle(cornerRadius: 10, style: .continuous)
    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
}

private enum NumberedDiffBlock {
  case run([NumberedLine])
  case gap(segmentIndex: Int, lines: [NumberedLine], position: GapPosition, state: GapRevealState)
}

struct NumberedDiffCard: View {
  let segments: [DiffSegment]

  @State private var revealed: [Int: GapRevealState] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    .background(diffCardBackground())
    .overlay(diffCardStroke())
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var blocks: [NumberedDiffBlock] {
    var result: [NumberedDiffBlock] = []
    var run: [NumberedLine] = []
    for (index, segment) in segments.enumerated() {
      switch segment {
      case .visible(let lines):
        run.append(contentsOf: lines)
      case .gap(let lines):
        let state = revealed[index] ?? .zero
        run.append(contentsOf: lines.prefix(state.fromTop))
        if lines.count - state.fromTop - state.fromBottom > 0 {
          if !run.isEmpty {
            result.append(.run(run))
            run = []
          }
          result.append(
            .gap(
              segmentIndex: index, lines: lines, position: gapPosition(index: index),
              state: state))
        }
        if state.fromBottom > 0 {
          run.append(contentsOf: lines.suffix(state.fromBottom))
        }
      }
    }
    if !run.isEmpty {
      result.append(.run(run))
    }
    return result
  }

  @ViewBuilder
  private func blockView(_ block: NumberedDiffBlock) -> some View {
    switch block {
    case .run(let lines):
      DiffRunView(lines: lines, gutter: .numbered)
    case .gap(let segmentIndex, let lines, let position, let state):
      gapRow(segmentIndex: segmentIndex, lines: lines, position: position, state: state)
    }
  }

  private func gapPosition(index: Int) -> GapPosition {
    if index == 0 { return .start }
    if index == segments.count - 1 { return .end }
    return .middle
  }

  private func gapRow(
    segmentIndex: Int, lines: [NumberedLine], position: GapPosition, state: GapRevealState
  ) -> some View {
    let total = lines.count
    let remaining = total - state.fromTop - state.fromBottom
    return HStack(spacing: 6) {
      Button {
        revealed[segmentIndex] = GapRevealState.reveal(
          current: state, total: total, position: position)
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "arrow.up.and.down")
          Text(FileDiffBuilder.gapTitle(hiddenCount: remaining, of: lines))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button("Show all") {
        revealed[segmentIndex] = GapRevealState(fromTop: total, fromBottom: 0)
      }
      .buttonStyle(LinkButtonStyle())
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(CountersignPalette.accentText)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Color.primary.opacity(0.04))
  }
}

private enum UnnumberedDiffBlock {
  case run([NumberedLine])
  case separator(String)
}

struct UnnumberedDiffCard: View {
  let lines: [DiffLine]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    .background(diffCardBackground())
    .overlay(diffCardStroke())
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var blocks: [UnnumberedDiffBlock] {
    var result: [UnnumberedDiffBlock] = []
    var run: [NumberedLine] = []
    for line in lines {
      guard let kind = numberedKind(for: line.kind) else {
        if !run.isEmpty {
          result.append(.run(run))
          run = []
        }
        result.append(.separator(line.text))
        continue
      }
      run.append(NumberedLine(kind: kind, text: line.text, oldNumber: nil, newNumber: nil))
    }
    if !run.isEmpty {
      result.append(.run(run))
    }
    return result
  }

  private func numberedKind(for kind: DiffLineKind) -> NumberedLineKind? {
    switch kind {
    case .context: return .context
    case .added: return .added
    case .removed: return .removed
    case .collapsed: return nil
    }
  }

  @ViewBuilder
  private func blockView(_ block: UnnumberedDiffBlock) -> some View {
    switch block {
    case .run(let lines):
      DiffRunView(lines: lines, gutter: .markerOnly)
    case .separator(let text):
      separatorRow(text)
    }
  }

  private func separatorRow(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 12, design: .monospaced))
      .italic()
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.04))
  }
}
