import ApprovalCore
import Foundation
import SwiftUI

enum PanelContextGauge {
  static func make(
    for request: ApprovalRequest, settings: ContextCheckpointSettings, paths: AppPaths, now: Date
  ) -> ContextGauge? {
    guard request.host == .claude, settings.enabled, let transcriptPath = request.transcriptPath,
      !request.isContextCheckpoint
    else { return nil }
    let reading = ContextUsageReader.read(transcriptURL: URL(fileURLWithPath: transcriptPath))
    let state =
      ContextCheckpointStore.isValidSessionID(request.sessionID)
      ? ContextCheckpointStore(directory: paths.contextCheckpointsDirectory)
        .load(sessionID: request.sessionID)
      : nil
    return ContextGauge.make(reading: reading, state: state, settings: settings, now: now)
  }
}

extension ApprovalRequest {
  fileprivate var isContextCheckpoint: Bool {
    guard case .contextCheckpoint = kind else { return false }
    return true
  }
}

struct ContextChip: View {
  let gauge: ContextGauge
  var cardOpenOnAppear = false

  private var sizeText: String { ContextCheckpointNotes.tokenText(gauge.tokens) }
  private var windowText: String {
    gauge.windowTokens >= ContextUsageReader.millionWindowTokens ? "1M" : "200K"
  }

  var body: some View {
    Chip(
      "\(sizeText) · \(gauge.windowPercent)%", symbol: "gauge.with.dots.needle.33percent",
      spokenLabel:
        "Context: \(sizeText) tokens, \(gauge.windowPercent) percent of the window"
    )
    .hoverCard(width: 300, startsOpen: cardOpenOnAppear) {
      Text("\(sizeText) of \(windowText) tokens in use (\(gauge.windowPercent)%).")
        .foregroundStyle(Color.primary)
      if !gauge.ladder.isEmpty {
        rungs
      }
      if let phrase = gauge.warmth.phrase {
        Text("Cache: \(phrase)")
      }
      if let modelID = gauge.modelID {
        Text("Model: \(modelID)")
      }
      Text(explanation)
    }
  }

  private var rungs: Text {
    let labelled = zip(ContextLevel.allCases, gauge.ladder).map { level, threshold in
      let text = Text("\(level.label) \(ContextCheckpointNotes.tokenText(threshold))")
      return gauge.passed.contains(level)
        ? text.foregroundStyle(Color.primary) : text.foregroundStyle(.secondary)
    }
    return labelled.dropFirst().reduce(labelled[0]) { joined, next in
      joined + Text(" · ").foregroundStyle(.secondary) + next
    }
  }

  private var explanation: String {
    let base =
      "How much of this Claude Code session's context is in use, read from its transcript, so it can lag a turn behind. At each checkpoint Countersign suggests a compact or a handoff"
    guard gauge.ladder.count >= ContextLevel.allCases.count else { return base + "." }
    return base + "; at the stop it asks Claude to stop and hand off."
  }
}

extension ContextLevel {
  fileprivate var label: String {
    switch self {
    case .soft: return "Soft"
    case .status: return "Status"
    case .insist: return "Insist"
    case .stop: return "Stop"
    }
  }
}
