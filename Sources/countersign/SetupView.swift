import AppKit
import ApprovalCore
import SwiftUI

@MainActor
@Observable
final class SetupModel {
  static let stepCount = 3
  static let unwrittenHookProblem = "Countersign could not write the hook."

  let settings: SettingsModel
  private(set) var step: Int
  private(set) var failures: [ApprovalCore.Host: String] = [:]
  private(set) var expandsDisclosures = false
  var requestDone: () -> Void = {}
  var requestOpenSettings: () -> Void = {}

  init(settings: SettingsModel) {
    self.settings = settings
    step = 1
    step = openingStep
  }

  var rows: [HostRow] { settings.hostRows }

  var agents: SetupAgents {
    SetupAgents(statuses: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.status) }))
  }

  var home: URL { settings.environment.home }

  var failedHosts: [ApprovalCore.Host] {
    ApprovalCore.Host.allCases.filter { failures[$0] != nil }
  }

  var shownRows: [HostRow] {
    rows.filter { $0.status != .notInstalled }
  }

  private var openingStep: Int {
    agents.phase == .allSet ? 3 : 1
  }

  func wire() {
    apply(to: agents.toWire)
  }

  func tryAgain() {
    apply(to: agents.toWire.filter { failures[$0] != nil })
  }

  func checkAgain() {
    settings.refreshFromDisk()
    failures = [:]
    step = openingStep
  }

  func next() {
    step = min(step + 1, Self.stepCount)
  }

  func back() {
    step = max(step - 1, 1)
  }

  func showTestPanel() {
    settings.showTestPanel(.command)
  }

  func expandDisclosuresForSnapshot() {
    expandsDisclosures = true
  }

  func showForSnapshot(step: Int, failures: [ApprovalCore.Host: String]) {
    self.step = step
    self.failures = failures
  }

  private func apply(to hosts: [ApprovalCore.Host]) {
    for host in hosts {
      settings.requestHostChange(host)
      settings.confirmHostChange()
    }
    settings.refreshFromDisk()
    var failed: [ApprovalCore.Host: String] = [:]
    for host in hosts {
      guard let row = rows.first(where: { $0.id == host }) else { continue }
      if row.error != nil || agents.toWire.contains(host) {
        failed[host] = row.problem ?? Self.unwrittenHookProblem
      }
    }
    failures = failed
    guard failed.isEmpty else { return }
    step = 2
    settings.showTestPanel(.command)
  }
}

struct SetupView: View {
  let model: SetupModel

  static let width: CGFloat = 460

  private var agents: SetupAgents { model.agents }
  private var isFailed: Bool { !model.failures.isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      content
      if model.step == 1, isFailed {
        InlineMessage(failureSummary, tone: .warning)
      }
      footer
    }
    .padding(24)
    .frame(width: Self.width, alignment: .leading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private static let intro =
    "When an agent asks for permission, Countersign shows a panel you can answer from any app."
    + " Wire your agents to send it those requests."
  private static let allSetIntro = "Every agent Countersign found is wired."
  private static let noAgentsIntro =
    "Countersign works with Claude Code, Codex, Cursor and Antigravity. Install one, then"
    + " check again."
  private static let tryItShowing =
    "A test panel is showing. Nothing you do in it reaches an agent."
  private static let makeItYours =
    "Delays, quiet hours, sounds and rules are in Settings. Every setting explains itself with ⓘ."

  private var failureSummary: String {
    let count = model.failures.count
    return count == 1
      ? "1 agent couldn't be wired. Countersign left its file unchanged."
      : "\(count) agents couldn't be wired. Countersign left their files unchanged."
  }

  @ViewBuilder
  private var content: some View {
    switch model.step {
    case 2:
      SetupHeading(title: "Try it", intro: nil)
      SetupTryIt(model: model, text: Self.tryItShowing)
    case 3:
      SetupHeading(title: "All set", intro: Self.allSetIntro)
      SetupAgentList(model: model)
      Text(Self.makeItYours)
        .font(PanelTypography.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    default:
      if agents.phase == .noAgents {
        SetupHeading(title: "No agents found", intro: Self.noAgentsIntro)
      } else {
        SetupHeading(title: "Wire your agents", intro: Self.intro)
        SetupAgentList(model: model)
      }
    }
  }

  private var stepCounter: String {
    "\(model.step) of \(SetupModel.stepCount)"
  }

  private var footer: some View {
    HStack(alignment: .center) {
      Text(stepCounter)
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      HStack(spacing: 8) {
        buttons
      }
    }
  }

  private var wireTitle: String {
    agents.toWire.count == 1
      ? "Wire \(agents.toWire.map(\.displayName).joined())" : "Wire \(agents.toWire.count) Agents"
  }

  @ViewBuilder
  private var buttons: some View {
    switch model.step {
    case 2:
      Button("Back", action: model.back).buttonStyle(SecondaryButtonStyle())
      Button("Next", action: model.next)
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    case 3:
      Button("Open Settings", action: model.requestOpenSettings)
        .buttonStyle(SecondaryButtonStyle())
      Button("Done", action: model.requestDone)
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    default:
      firstStepButtons
    }
  }

  @ViewBuilder
  private var firstStepButtons: some View {
    if agents.phase == .noAgents {
      Button("Not Now", action: model.requestDone).buttonStyle(SecondaryButtonStyle())
      Button("Check Again", action: model.checkAgain)
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    } else if isFailed {
      Button("Done", action: model.requestDone).buttonStyle(SecondaryButtonStyle())
      Button("Open Settings", action: model.requestOpenSettings)
        .buttonStyle(SecondaryButtonStyle())
      Button("Try Again", action: model.tryAgain)
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    } else if agents.toWire.isEmpty {
      Button("Not Now", action: model.requestDone).buttonStyle(SecondaryButtonStyle())
      Button("Next", action: model.next)
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    } else {
      Button("Not Now", action: model.requestDone).buttonStyle(SecondaryButtonStyle())
      Button(wireTitle, action: model.wire)
        .buttonStyle(PrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    }
  }
}

private struct SetupHeading: View {
  let title: String
  let intro: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 16, weight: .semibold))
      if let intro {
        Text(intro)
          .font(PanelTypography.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct SetupAgentList: View {
  let model: SetupModel

  var body: some View {
    let shown = model.shownRows
    VStack(alignment: .leading, spacing: 8) {
      SettingsGroup {
        ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
          if index > 0 { SettingsDivider() }
          SetupAgentRow(
            row: row, home: model.home, needsWiring: model.agents.toWire.contains(row.id),
            failure: model.failures[row.id], startsExpanded: model.expandsDisclosures)
        }
      }
      if !model.agents.notInstalled.isEmpty {
        Text(
          "Not installed: \(model.agents.notInstalled.map(\.displayName).joined(separator: ", "))"
        )
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
      }
    }
  }
}

private struct SetupAgentRow: View {
  let row: HostRow
  let home: URL
  let needsWiring: Bool
  let failure: String?

  @State private var expanded: Bool

  init(row: HostRow, home: URL, needsWiring: Bool, failure: String?, startsExpanded: Bool) {
    self.row = row
    self.home = home
    self.needsWiring = needsWiring
    self.failure = failure
    _expanded = State(initialValue: startsExpanded)
  }

  private static let detailIndent = SettingsMetrics.glyphWidth + 10

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: glyph)
          .font(.system(size: 15))
          .foregroundStyle(glyphColor)
          .frame(width: SettingsMetrics.glyphWidth)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(row.id.displayName)
            .font(.system(size: 13, weight: .semibold))
          Text(statusText)
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)
      }
      detail
    }
    .padding(SettingsMetrics.rowPadding)
  }

  @ViewBuilder
  private var detail: some View {
    if let failure {
      detailText(failure)
    } else if case .unusable(let reason) = row.status {
      detailText(reason)
    } else if needsWiring {
      VStack(alignment: .leading, spacing: 6) {
        Text("Countersign adds a hook to \(row.shownPath(home: home)).")
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let preview = row.preview {
          ChangesDisclosure(
            isExpanded: expanded,
            subject: "the change (\(DiffSummary(unifiedDiff: preview.text).text))",
            toggle: { expanded.toggle() })
          if expanded {
            HookDiffPreviewView(text: preview.text)
          }
        }
      }
      .padding(.leading, Self.detailIndent)
    } else if row.status == .wired, let followUp = row.followUp, followUp.kind == .nextStep {
      detailText(followUp.text)
    }
  }

  private func detailText(_ text: String) -> some View {
    Text(text)
      .font(PanelTypography.secondary)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.leading, Self.detailIndent)
  }

  private var statusText: String {
    failure == nil ? HostWiring.title(for: row.status) : "Couldn't be wired"
  }

  private var glyph: String {
    if failure != nil { return "exclamationmark.triangle.fill" }
    switch row.status {
    case .notInstalled: return "minus.circle"
    case .notWired: return "circle.dashed"
    case .wired: return "checkmark.circle.fill"
    case .needsUpdate: return "arrow.triangle.2.circlepath.circle.fill"
    case .unusable: return "exclamationmark.triangle.fill"
    }
  }

  private var glyphColor: Color {
    if failure != nil { return Color(nsColor: .systemRed) }
    switch row.status {
    case .notInstalled, .notWired: return .secondary
    case .wired: return Color(nsColor: .systemGreen)
    case .needsUpdate: return Color(nsColor: .systemOrange)
    case .unusable: return Color(nsColor: .systemRed)
    }
  }
}

private struct SetupTryIt: View {
  let model: SetupModel
  let text: String

  private static let segments: [SetupKeySegment] = [
    .key("⏎"), .text(" approves, "), .key("esc"), .text(" answers in the chat, "), .key("⌫"),
    .text(" opens Deny and "), .key("⌘⏎"), .text(" opens more choices."),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(text)
        .font(PanelTypography.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      SetupKeysLine(segments: Self.segments)
        .foregroundStyle(.secondary)
      if let problem = model.settings.testPanelError {
        InlineMessage(problem, tone: .problem)
      }
      Button("Show a Test Panel", action: model.showTestPanel)
        .buttonStyle(SecondaryButtonStyle())
        .padding(.top, 4)
    }
  }
}

private enum SetupKeySegment {
  case text(String)
  case key(String)
}

private struct SetupKeysLine: View {
  let segments: [SetupKeySegment]

  private enum Token {
    case word(String)
    case key(String)
  }

  private var tokens: [Token] {
    segments.flatMap { segment in
      switch segment {
      case .text(let text):
        return text.split(separator: " ").map { Token.word(String($0)) }
      case .key(let key):
        return [Token.key(key)]
      }
    }
  }

  var body: some View {
    KeyHintFlowLayout(spacing: 5) {
      ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
        switch token {
        case .word(let word):
          Text(word)
            .font(PanelTypography.body)
        case .key(let key):
          KeyHint(key, placement: .link)
        }
      }
    }
  }
}

struct HookDiffPreviewView: NSViewRepresentable {
  let text: String

  func makeNSView(context: Context) -> NSView {
    HookDiffPreview.view(text: text)
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
    let width = min(proposal.width ?? HookDiffPreview.width, HookDiffPreview.width)
    let height = HookDiffPreview.view(text: text, width: width).frame.height
    return CGSize(width: width, height: height)
  }
}
