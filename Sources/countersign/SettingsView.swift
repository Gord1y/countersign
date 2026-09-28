import AppKit
import ApprovalCore
import SwiftUI

enum SettingsMetrics {
  static let padding: CGFloat = 24
  static let sectionSpacing: CGFloat = 28
  static let headerSpacing: CGFloat = 16
  static let rowPadding: CGFloat = 14
  static let glyphWidth: CGFloat = 18
  static let cornerRadius: CGFloat = 10
  static let sidebarWidth: CGFloat = 170
}

struct SettingsRootView: View {
  let model: SettingsModel

  var body: some View {
    SettingsPage(model: model)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Color(nsColor: .windowBackgroundColor))
  }
}

struct SettingsPage: View {
  let model: SettingsModel

  var body: some View {
    VStack(spacing: 0) {
      SettingsHeader(model: model)
      HStack(alignment: .top, spacing: SettingsMetrics.sectionSpacing) {
        SettingsSidebar(model: model)
          .frame(width: SettingsMetrics.sidebarWidth, alignment: .leading)
        ScrollView(.vertical) {
          SettingsContent(model: model)
            .background(ScrollElasticityDisabler())
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.visible)
        .id(model.selectedPane.rawValue)
      }
      .padding(.horizontal, SettingsMetrics.padding)
    }
  }
}

private struct ScrollElasticityDisabler: NSViewRepresentable {
  func makeNSView(context: Context) -> ScrollElasticityDisablerView {
    ScrollElasticityDisablerView()
  }

  func updateNSView(_ nsView: ScrollElasticityDisablerView, context: Context) {
    nsView.disableVerticalElasticity()
  }
}

private final class ScrollElasticityDisablerView: NSView {
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    disableVerticalElasticity()
  }

  override func layout() {
    super.layout()
    disableVerticalElasticity()
  }

  func disableVerticalElasticity() {
    enclosingScrollView?.verticalScrollElasticity = .none
  }
}

struct SettingsHeader: View {
  let model: SettingsModel

  var body: some View {
    VStack(spacing: SettingsMetrics.headerSpacing) {
      HStack(spacing: 8) {
        CountersignMark()
          .frame(width: 20, height: 20)
        Text("Countersign")
          .font(.system(size: 13, weight: .semibold))
        Text(CountersignVersion.current)
          .font(PanelTypography.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
        Spacer(minLength: 12)
        Button("Close") { model.requestClose?() }
          .buttonStyle(SecondaryButtonStyle())
      }
      StatusRow(model: model)
    }
    .padding(.horizontal, SettingsMetrics.padding)
    .padding(.top, SettingsMetrics.padding)
    .padding(.bottom, SettingsMetrics.sectionSpacing)
    .frame(maxWidth: .infinity)
  }
}

struct SettingsSidebar: View {
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(SettingsPane.sidebar, id: \.self) { pane in
        SettingsSidebarRow(pane: pane, isSelected: isSelected(pane)) {
          model.select(pane)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private func isSelected(_ pane: SettingsPane) -> Bool {
    pane == model.selectedPane || (pane == .app && model.selectedPane == .advanced)
  }
}

private struct SettingsSidebarRow: View {
  let pane: SettingsPane
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 13))
          .frame(width: 18)
        Text(pane.title)
          .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        Spacer(minLength: 0)
      }
      .foregroundStyle(isSelected ? CountersignPalette.accentText : Color.primary)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(isSelected ? CountersignPalette.accentText.opacity(0.12) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var icon: String {
    switch pane {
    case .agents: return "person.2"
    case .app: return "macwindow"
    case .panels: return "rectangle.stack"
    case .help: return "questionmark.circle"
    case .advanced: return "slider.horizontal.3"
    }
  }
}

struct SettingsContent: View {
  let model: SettingsModel

  var body: some View {
    SettingsPaneView(pane: model.selectedPane, model: model)
      .padding(.bottom, SettingsMetrics.padding)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct SettingsPaneView: View {
  let pane: SettingsPane
  let model: SettingsModel

  var body: some View {
    switch pane {
    case .agents: AgentsSection(model: model)
    case .panels: PanelsSection(model: model)
    case .app: AppSection(model: model)
    case .help: HelpSection(model: model)
    case .advanced: AdvancedSection(model: model)
    }
  }
}

struct SettingsSection<Content: View>: View {
  let subtitle: String
  let content: Content

  init(_ pane: SettingsPane, @ViewBuilder content: () -> Content) {
    self.subtitle = pane.subtitle
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(subtitle)
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct SettingsGroup<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
    .overlay(
      RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    )
  }
}

struct SettingsDivider: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.08))
      .frame(height: 1)
      .padding(.leading, SettingsMetrics.rowPadding)
  }
}

struct InlineMessage: View {
  enum Tone {
    case problem
    case warning
    case note
    case done
  }

  let text: String
  let tone: Tone

  init(_ text: String, tone: Tone) {
    self.text = text
    self.tone = tone
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 11))
        .foregroundStyle(color)
      Text(text)
        .font(PanelTypography.secondary)
        .foregroundStyle(textColor)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
        .help(text)
    }
  }

  private var symbol: String {
    switch tone {
    case .problem, .warning: return "exclamationmark.triangle.fill"
    case .note: return "info.circle"
    case .done: return "checkmark.circle.fill"
    }
  }

  private var color: Color {
    switch tone {
    case .problem: return Color(nsColor: .systemRed)
    case .warning: return Color(nsColor: .systemOrange)
    case .note: return .secondary
    case .done: return Color(nsColor: .systemGreen)
    }
  }

  private var textColor: Color {
    switch tone {
    case .problem: return color
    case .warning: return .primary
    case .note, .done: return .secondary
    }
  }
}

struct StatusRow: View {
  let model: SettingsModel

  var body: some View {
    SettingsGroup {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 10) {
          Image(systemName: model.status.icon.symbolName)
            .font(.system(size: 15))
            .foregroundStyle(glyphColor)
            .frame(width: SettingsMetrics.glyphWidth)
            .accessibilityLabel(model.status.icon.accessibilityLabel)
          VStack(alignment: .leading, spacing: 2) {
            Text(model.status.title())
              .font(.system(size: 13, weight: .semibold))
            Text(model.status.detail)
              .font(PanelTypography.secondary)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 12)
          actionButton
        }
        if let error = model.statusError {
          InlineMessage(error, tone: .problem)
            .padding(.leading, SettingsMetrics.glyphWidth + 10)
        }
      }
      .padding(SettingsMetrics.rowPadding)
    }
  }

  @ViewBuilder
  private var actionButton: some View {
    let action = model.status.action
    switch action {
    case .pause:
      Button(action.title) { model.performStatusAction() }
        .buttonStyle(SecondaryButtonStyle())
    case .resume, .endQuietTime:
      Button(action.title) { model.performStatusAction() }
        .buttonStyle(PrimaryButtonStyle())
    }
  }

  private var glyphColor: Color {
    switch model.status {
    case .active: return Color(nsColor: .systemGreen)
    case .paused, .pausedUntilAppOpens: return Color(nsColor: .systemOrange)
    case .quiet: return Color(nsColor: .systemIndigo)
    }
  }
}

struct AgentsSection: View {
  let model: SettingsModel

  var body: some View {
    SettingsSection(.agents) {
      if let mismatch = model.installVersionMismatch {
        InstallVersionMismatchNotice(mismatch: mismatch, model: model)
      }
      if let duplicateInstall = model.duplicateInstall {
        DuplicateInstallNotice(duplicateInstall: duplicateInstall, model: model)
      }
      SettingsGroup {
        ForEach(Array(model.hostRows.enumerated()), id: \.element.id) { index, row in
          if index > 0 {
            SettingsDivider()
          }
          HostRowView(row: row, model: model)
        }
      }
    }
  }
}

private struct HostRowView: View {
  let row: HostRow
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: glyph)
          .font(.system(size: 15))
          .foregroundStyle(glyphColor)
          .frame(width: SettingsMetrics.glyphWidth)
        VStack(alignment: .leading, spacing: 2) {
          Text(row.location.host.displayName)
            .font(.system(size: 13, weight: .semibold))
          Text(
            "\(HostWiring.title(for: row.status)) · \(row.shownPath(home: model.environment.home))"
          )
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
        }
        Spacer(minLength: 12)
        actionButton
      }
      VStack(alignment: .leading, spacing: 8) {
        if case .unusable(let reason) = row.status {
          InlineMessage(reason, tone: .problem)
        } else if let detail = HostWiring.detail(for: row.status, host: row.location.host) {
          Text(detail)
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let note = model.ownValueNotes[row.id] {
          OwnValuesNote(note: note, host: row.id, model: model)
        }
        if row.preview?.hasChanges == true {
          ChangesDisclosure(isExpanded: row.showsChanges) {
            model.toggleChanges(row.id)
          }
          if row.showsChanges, let preview = row.preview {
            SetupDiffView(text: preview.text)
          }
        }
        if let problem = row.problem {
          InlineMessage(problem, tone: .problem)
        }
        if let followUp = row.followUp {
          AgentFollowUpView(followUp: followUp, model: model)
        }
      }
      .padding(.leading, SettingsMetrics.glyphWidth + 10)
    }
    .padding(SettingsMetrics.rowPadding)
  }

  @ViewBuilder
  private var actionButton: some View {
    if let action = row.action {
      switch action {
      case .wire, .update:
        Button(action.title) { model.apply(row.id) }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(!row.canApply)
      case .remove:
        Button(action.title) { model.apply(row.id) }
          .buttonStyle(LinkButtonStyle())
          .disabled(!row.canApply)
      }
    }
  }

  private var glyph: String {
    switch row.status {
    case .notInstalled: return "minus.circle"
    case .notWired: return "circle.dashed"
    case .wired: return "checkmark.circle.fill"
    case .needsUpdate: return "arrow.triangle.2.circlepath.circle.fill"
    case .unusable: return "exclamationmark.triangle.fill"
    }
  }

  private var glyphColor: Color {
    switch row.status {
    case .notInstalled, .notWired: return .secondary
    case .wired: return Color(nsColor: .systemGreen)
    case .needsUpdate: return Color(nsColor: .systemOrange)
    case .unusable: return Color(nsColor: .systemRed)
    }
  }
}

private struct OwnValuesNote: View {
  let note: String
  let host: ApprovalCore.Host
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "doc.text")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Text(note)
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        Button("Open in Editor") { model.openConfigInEditor(from: .host(host)) }
          .buttonStyle(.link)
          .font(PanelTypography.secondary)
          .fixedSize()
        Spacer(minLength: 0)
      }
      if let problem = model.editorOpenProblem(at: .host(host)) {
        InlineMessage(problem, tone: .problem)
      }
    }
  }
}

private struct AgentFollowUpView: View {
  let followUp: AgentFollowUp
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 11))
          .foregroundStyle(symbolColor)
        (Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(labelColor)
          + Text(" " + followUp.text).font(PanelTypography.secondary).foregroundStyle(.secondary))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
      if followUp.offersMarkAsDone {
        Button("Mark as done") { model.markCodexHookTrustAsDone() }
          .buttonStyle(SecondaryButtonStyle())
      }
    }
  }

  private var symbol: String {
    followUp.kind == .nextStep ? "arrow.right.circle.fill" : "info.circle"
  }

  private var symbolColor: Color {
    followUp.kind == .nextStep ? CountersignPalette.accentText : .secondary
  }

  private var label: String {
    followUp.kind == .nextStep ? "Next step" : "Good to know"
  }

  private var labelColor: Color {
    followUp.kind == .nextStep ? .primary : .secondary
  }
}

struct ChangesDisclosure: View {
  let isExpanded: Bool
  var subject = "changes"
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 4) {
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
        Text(isExpanded ? "Hide \(subject)" : "Show \(subject)")
      }
      .font(PanelTypography.secondary)
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct SetupDiffView: View {
  let text: String

  var body: some View {
    CodeCard {
      ScrollView(.horizontal) {
        Text(Self.styled(text))
          .font(PanelTypography.code)
          .textSelection(.enabled)
          .fixedSize()
      }
    }
  }

  static func styled(_ text: String) -> AttributedString {
    let lines = text.hasSuffix("\n") ? String(text.dropLast()) : text
    var result = AttributedString()
    for (index, line) in lines.split(separator: "\n", omittingEmptySubsequences: false)
      .enumerated()
    {
      if index > 0 {
        result += AttributedString("\n")
      }
      var part = AttributedString(String(line))
      if line.hasPrefix("+"), !line.hasPrefix("+++") {
        part.foregroundColor = Color(nsColor: .systemGreen)
      } else if line.hasPrefix("-"), !line.hasPrefix("---") {
        part.foregroundColor = Color(nsColor: .systemRed)
      } else if line.hasPrefix("@@") || line.hasPrefix("---") || line.hasPrefix("+++") {
        part.foregroundColor = .secondary
      }
      result += part
    }
    return result
  }
}
