import AppKit
import ApprovalCore
import SwiftUI

enum SettingsMetrics {
  static let padding: CGFloat = 24
  static let sectionSpacing: CGFloat = 28
  static let headerVerticalPadding: CGFloat = 12
  static let contentTopInset: CGFloat = 16
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
        SettingsScrollView(model: model, pane: model.selectedPane)
      }
      .padding(.horizontal, SettingsMetrics.padding)
    }
    .sheet(
      item: Binding(
        get: { model.editorChoice },
        set: { if $0 == nil { model.cancelEditorChoice() } })
    ) { choice in
      EditorChoiceSheet(
        choice: choice, configFile: model.configFile,
        onOpen: { model.chooseEditor(bundleID: $0, always: $1) },
        onCancel: { model.cancelEditorChoice() })
    }
  }
}

private struct SettingsScrollView: NSViewRepresentable {
  let model: SettingsModel
  let pane: SettingsPane

  func makeCoordinator() -> Coordinator {
    Coordinator(pane: pane)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = false
    scrollView.verticalScrollElasticity = .none
    scrollView.horizontalScrollElasticity = .none
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder

    let documentView = SettingsDocumentView(model: model)
    documentView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = documentView

    let clipView = scrollView.contentView
    NSLayoutConstraint.activate([
      documentView.topAnchor.constraint(equalTo: clipView.topAnchor),
      documentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      documentView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
      documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
    ])
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard context.coordinator.pane != pane else { return }
    context.coordinator.pane = pane
    scrollView.contentView.scroll(to: .zero)
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }

  final class Coordinator {
    var pane: SettingsPane

    init(pane: SettingsPane) {
      self.pane = pane
    }
  }
}

private struct SettingsDocumentContent: View {
  let model: SettingsModel
  let width: CGFloat?

  var body: some View {
    SettingsContent(model: model)
      .fixedSize(horizontal: false, vertical: true)
      .frame(width: width)
      .frame(maxHeight: .infinity, alignment: .top)
  }
}

private final class SettingsDocumentView: NSView {
  private let model: SettingsModel
  private let hostingView: NSHostingView<SettingsDocumentContent>

  init(model: SettingsModel) {
    self.model = model
    hostingView = NSHostingView(rootView: SettingsDocumentContent(model: model, width: nil))
    super.init(frame: .zero)
    hostingView.sizingOptions = [.intrinsicContentSize]
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SettingsDocumentView does not support NSCoding")
  }

  override var isFlipped: Bool { true }

  override func layout() {
    super.layout()
    let width = bounds.width
    guard width > 0, hostingView.rootView.width != width else { return }
    hostingView.rootView = SettingsDocumentContent(model: model, width: width)
  }
}

struct SettingsHeader: View {
  let model: SettingsModel

  var body: some View {
    let controls = model.headerControls
    VStack(alignment: .leading, spacing: 6) {
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
        if let caption = controls.caption() {
          Text(caption.text)
            .font(PanelTypography.caption)
            .foregroundStyle(caption.tint.color)
            .lineLimit(1)
        }
        HeaderPauseButton(model: model, controls: controls)
        HeaderSnoozeButton(model: model, controls: controls)
        Button("Close") { model.requestClose?() }
          .buttonStyle(SecondaryButtonStyle())
      }
      if let error = model.statusError {
        InlineMessage(error, tone: .problem)
      }
    }
    .padding(.horizontal, SettingsMetrics.padding)
    .padding(.vertical, SettingsMetrics.headerVerticalPadding)
    .frame(maxWidth: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .bottom) {
      SettingsHairline(opacity: 0.12)
    }
    .zIndex(1)
  }
}

extension HeaderControlTint {
  fileprivate var color: Color {
    switch self {
    case .secondary: return .secondary
    case .yellow: return Color(nsColor: .systemYellow)
    case .amber:
      return Color(
        nsColor: NSColor(name: nil) { appearance in
          if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return .systemYellow
          }
          return NSColor(srgbRed: 0.55, green: 0.36, blue: 0, alpha: 1)
        })
    case .blue: return Color(nsColor: .systemBlue)
    }
  }
}

private struct HeaderIconButton: View {
  let symbol: String
  let tint: HeaderControlTint
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(tint.color)
        .frame(width: 28, height: 28)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.06))
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
  }
}

private struct HeaderPauseButton: View {
  let model: SettingsModel
  let controls: SettingsHeaderControls

  var body: some View {
    HeaderIconButton(
      symbol: "pause.fill", tint: controls.pauseTint, help: controls.pauseHelp
    ) {
      model.togglePause()
    }
    .accessibilityValue(controls.pauseAccessibilityValue)
  }
}

private struct HeaderSnoozeButton: View {
  let model: SettingsModel
  let controls: SettingsHeaderControls

  @State private var isPresented = false

  var body: some View {
    HeaderIconButton(
      symbol: "moon.zzz", tint: controls.snoozeTint, help: controls.snoozeHelp
    ) {
      isPresented = true
    }
    .disabled(!controls.snoozeIsEnabled)
    .opacity(controls.snoozeIsEnabled ? 1 : 0.4)
    .popover(isPresented: $isPresented, arrowEdge: .bottom) {
      SnoozePopoverView(model: model, controls: controls) { isPresented = false }
    }
  }
}

private struct SnoozePopoverView: View {
  let model: SettingsModel
  let controls: SettingsHeaderControls
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let heading = controls.quietHeading() {
        Text(heading)
          .font(.system(size: 13, weight: .semibold))
          .padding(.horizontal, 8)
          .padding(.bottom, 4)
        SnoozePopoverRow(title: "End now") {
          model.endQuietTime()
          dismiss()
        }
      } else {
        ForEach(Array(model.snoozeChoices.enumerated()), id: \.offset) { index, seconds in
          SnoozePopoverRow(title: SnoozeTitle.describe(seconds: seconds, isFirst: index == 0)) {
            model.snooze(seconds: seconds)
            dismiss()
          }
        }
      }
    }
    .padding(8)
    .frame(minWidth: 180, alignment: .leading)
  }
}

private struct SnoozePopoverRow: View {
  let title: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

struct SettingsSidebar: View {
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(SettingsPane.sidebar(showsContext: model.contextCheckpointsEnabled), id: \.self) {
        pane in
        SettingsSidebarRow(pane: pane, isSelected: isSelected(pane)) {
          model.select(pane)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.top, SettingsMetrics.contentTopInset)
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
          .accessibilityHidden(true)
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
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var icon: String {
    switch pane {
    case .agents: return "person.2"
    case .app: return "macwindow"
    case .panels: return "rectangle.stack"
    case .rules: return "checklist"
    case .context: return "gauge.with.dots.needle.33percent"
    case .help: return "questionmark.circle"
    case .advanced: return "slider.horizontal.3"
    }
  }
}

struct SettingsContent: View {
  let model: SettingsModel

  var body: some View {
    SettingsPaneView(pane: model.selectedPane, model: model)
      .padding(.top, SettingsMetrics.contentTopInset)
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
    case .rules: RulesSection(model: model)
    case .context: ContextSection(model: model)
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

struct SettingsHairline: View {
  let opacity: Double

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    Rectangle()
      .fill(
        contrast == .increased ? Color(nsColor: .separatorColor) : Color.primary.opacity(opacity)
      )
      .frame(height: 1)
  }
}

struct SettingsGroup<Content: View>: View {
  let content: Content

  @Environment(\.colorSchemeContrast) private var contrast

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
        .stroke(
          contrast == .increased ? Color(nsColor: .separatorColor) : Color.primary.opacity(0.08),
          lineWidth: 1)
    )
  }
}

struct SettingsDivider: View {
  var body: some View {
    SettingsHairline(opacity: 0.08)
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
        .accessibilityHidden(true)
      Text(text)
        .font(PanelTypography.secondary)
        .foregroundStyle(textColor)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
        .help(text)
    }
    .accessibilityElement(children: .combine)
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
    .modifier(HostHookPromptPresenter(model: model))
  }
}

private struct HostHookPromptPresenter: ViewModifier {
  let model: SettingsModel

  func body(content: Content) -> some View {
    content.onChange(of: model.hostChange != nil) { _, isPending in
      guard isPending, let change = model.hostChange else { return }
      HostHookPrompt.present(
        change: change, home: model.homeDirectory, on: NSApp.keyWindow,
        onConfirm: { model.confirmHostChange() },
        onCancel: { model.cancelHostChange() })
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
          .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
        Spacer(minLength: 12)
        actionButton
      }
      Group {
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
        Button(action.title) { model.requestHostChange(row.id) }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(!row.canApply || model.hostChange != nil)
      case .remove:
        Button(action.title) { model.requestHostChange(row.id) }
          .buttonStyle(LinkButtonStyle())
          .disabled(!row.canApply || model.hostChange != nil)
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
          .accessibilityHidden(true)
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
          .accessibilityHidden(true)
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
          .accessibilityHidden(true)
        Text(isExpanded ? "Hide \(subject)" : "Show \(subject)")
      }
      .font(PanelTypography.secondary)
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
