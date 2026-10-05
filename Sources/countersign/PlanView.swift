import ApprovalCore
import SwiftUI

struct PlanView: View {
  let model: PanelModel
  let plan: PlanProposal
  let availableHeight: CGFloat

  @State private var mode: PlanApprovalMode
  @State private var feedback = ""
  @State private var showingFeedback = false
  @FocusState private var isFeedbackFieldFocused: Bool

  init(model: PanelModel, plan: PlanProposal, availableHeight: CGFloat) {
    self.model = model
    self.plan = plan
    self.availableHeight = availableHeight
    _mode = State(initialValue: model.modeAfterPlan)
  }

  private var blocks: [MarkdownBlock] {
    MarkdownBlocks.parse(plan.plan)
  }

  var body: some View {
    PanelScaffold(model: model, availableHeight: availableHeight) {
      VStack(alignment: .leading, spacing: 8) {
        if let planFilePath = plan.planFilePath {
          HStack(spacing: 6) {
            Image(systemName: "doc.text")
              .accessibilityHidden(true)
            Text(planFilePath)
              .fixedSize(horizontal: false, vertical: true)
          }
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
            blockView(block)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    } footer: {
      footer
    }
    .onAppear {
      model.keyHandler = PanelKeyHandler(uses: usesKey, perform: handleKey)
      if model.dropdown.takeRequest(for: .mode) {
        toggleModeDropdown()
      }
    }
  }

  private func toggleModeDropdown() {
    let modes = PlanApprovalMode.allCases
    let rows = modes.map { candidate in
      PanelDropdownRow(title: candidate.title, isChecked: candidate == mode)
    }
    let menu = PanelDropdownMenu(
      id: .mode, direction: .up, rows: rows, startRow: modes.firstIndex(of: mode) ?? 0
    ) { row in
      guard model.isArmed, modes.indices.contains(row) else { return }
      mode = modes[row]
    }
    model.dropdown.toggle(menu)
  }

  private func approve() {
    model.finish(PlanResponse.approve(toolInput: model.request.toolInput, mode: mode))
  }

  private func sendFeedback() {
    model.finish(PlanResponse.keepPlanning(feedback: feedback))
  }

  private func usesKey(_ key: PanelKey) -> Bool {
    switch key {
    case .primary: return true
    case .secondary: return !showingFeedback
    case .alternate: return !showingFeedback
    case .digit, .left, .right, .up, .down: return false
    }
  }

  private func handleKey(_ key: PanelKey) {
    guard usesKey(key) else { return }
    switch key {
    case .primary:
      if showingFeedback {
        sendFeedback()
      } else {
        approve()
      }
    case .secondary:
      showingFeedback = true
    case .alternate:
      toggleModeDropdown()
    case .digit, .left, .right, .up, .down:
      break
    }
  }

  @ViewBuilder
  private func blockView(_ block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      headingView(level: level, text: text)
    case .bullet(let indent, let text):
      HStack(alignment: .top, spacing: 8) {
        Circle()
          .fill(CountersignPalette.accentText)
          .frame(width: 5, height: 5)
          .padding(.top, 6)
          .accessibilityHidden(true)
        inlineText(text)
          .font(.system(size: 13))
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, CGFloat(indent) * 16)
    case .numbered(let indent, let number, let text):
      HStack(alignment: .top, spacing: 8) {
        Text("\(number).")
          .font(.system(size: 13, weight: .semibold, design: .monospaced))
          .foregroundStyle(CountersignPalette.accentText)
        inlineText(text)
          .font(.system(size: 13))
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, CGFloat(indent) * 16)
    case .code(_, let text):
      CodeCard {
        Text(text)
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .rule:
      Rectangle()
        .fill(Color.primary.opacity(0.1))
        .frame(height: 1)
        .accessibilityHidden(true)
    case .paragraph(let text):
      inlineText(text)
        .font(.system(size: 13))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func headingView(level: Int, text: String) -> some View {
    let font: Font
    let topPadding: CGFloat
    switch level {
    case 1:
      font = .system(size: 20, weight: .semibold)
      topPadding = 0
    case 2:
      font = .system(size: 16, weight: .semibold)
      topPadding = 6
    case 3:
      font = .system(size: 14, weight: .semibold)
      topPadding = 0
    default:
      font = .system(size: 13, weight: .semibold)
      topPadding = 0
    }
    return inlineText(text)
      .font(font)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, topPadding)
  }

  private func inlineText(_ text: String) -> Text {
    if let attributed = try? AttributedString(
      markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    {
      return Text(attributed)
    }
    return Text(text)
  }

  private var footer: some View {
    ZStack(alignment: .bottom) {
      defaultFooter
        .opacity(showingFeedback ? 0 : 1)
        .allowsHitTesting(!showingFeedback)
        .accessibilityHidden(showingFeedback)
      feedbackFooter
        .opacity(showingFeedback ? 1 : 0)
        .allowsHitTesting(showingFeedback)
        .accessibilityHidden(!showingFeedback)
    }
    .onChange(of: showingFeedback) { _, isShowing in
      isFeedbackFieldFocused = isShowing
    }
  }

  private var defaultFooter: some View {
    HStack {
      AnswerInChatButton(model: model)

      Spacer()

      Button {
        showingFeedback = true
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text("Keep planning")
            .keyHintTextGuide(capHeight: SecondaryButtonStyle.labelCapHeight)
          KeyHint("⌫", placement: .onSecondary)
            .keyHintGuide()
        }
      }
      .buttonStyle(SecondaryButtonStyle())
      .panelButtonAccessibility(shortcut: "⌫")
      .disabled(!model.isArmed)

      Button(action: toggleModeDropdown) {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          HStack(spacing: 4) {
            Text("then: \(mode.title)")
            Image(systemName: "chevron.down")
              .font(.system(size: 9, weight: .semibold))
              .accessibilityHidden(true)
          }
          .keyHintTextGuide(capHeight: LinkButtonStyle.labelCapHeight)
          KeyHint("⌘⏎", placement: .link)
            .keyHintGuide()
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .font(PanelTypography.secondary)
      .foregroundStyle(.secondary)
      .panelButtonAccessibility(shortcut: "⌘⏎")
      .disabled(!model.isArmed)
      .panelDropdownAnchor(.mode)

      Button {
        approve()
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text("Approve")
            .keyHintTextGuide(capHeight: PrimaryButtonStyle.labelCapHeight)
          KeyHint("⏎", placement: .onAccent)
            .keyHintGuide()
        }
      }
      .buttonStyle(PrimaryButtonStyle())
      .panelPrimaryAccessibility(shortcut: "⏎", model: model)
      .disabled(!model.isArmed || showingFeedback)
    }
  }

  private var feedbackFooter: some View {
    HStack(spacing: 8) {
      Button("Back") {
        showingFeedback = false
      }
      .buttonStyle(LinkButtonStyle())
      .disabled(!model.isArmed)

      TextField("What should change?", text: $feedback, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(1...4)
        .focused($isFeedbackFieldFocused)
        .disabled(!model.isArmed || !showingFeedback)

      Button {
        sendFeedback()
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text("Send feedback")
            .keyHintTextGuide(capHeight: SecondaryButtonStyle.labelCapHeight)
          KeyHint("⏎", placement: .onSecondary)
            .keyHintGuide()
        }
      }
      .buttonStyle(SecondaryButtonStyle())
      .panelButtonAccessibility(shortcut: "⏎")
      .disabled(!model.isArmed)
    }
  }
}
