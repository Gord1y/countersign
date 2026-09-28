import ApprovalCore
import SwiftUI

private enum PermissionFooterState: Sendable, Equatable {
  case `default`
  case deny
}

struct PermissionView: View {
  let model: PanelModel
  let prompt: PermissionPrompt
  let availableHeight: CGFloat

  @State private var footerState: PermissionFooterState = .default
  @State private var reasonText = ""
  @FocusState private var isReasonFieldFocused: Bool

  private var host: ApprovalCore.Host { model.request.host }
  private var fileDiffs: [FileDiff]? { model.fileDiffs }

  private var reasonPlaceholder: String {
    switch host {
    case .claude: return "Tell Claude why (optional)"
    case .codex: return "Tell Codex why (optional)"
    case .cursor: return "Tell Cursor why (optional)"
    case .antigravity: return "Tell Antigravity why (optional)"
    }
  }

  private func fileName(_ path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
  }

  private var title: String {
    switch prompt.body {
    case .bash:
      return "Run a command"
    case .edit(let path, _, _, _):
      return "Edit \(fileName(path))"
    case .write(let path, _):
      let overwriting = fileDiffs?.first?.status == .modified
      return overwriting ? "Overwrite \(fileName(path))" : "Create \(fileName(path))"
    case .patch(let text):
      let count = PatchParser.files(inApplyPatch: text).count
      return count > 1 ? "Apply a patch · \(count) files" : "Apply a patch"
    case .webFetch:
      return "Fetch a web page"
    case .mcp(let server, let tool, _):
      return "\(server) · \(tool)"
    case .json:
      return model.request.toolName
    }
  }

  private var subtitle: String? {
    switch prompt.body {
    case .bash(_, let description):
      return description
    case .edit(let path, _, _, _):
      return fileDiffs == nil ? path : nil
    case .write(let path, _):
      return fileDiffs == nil ? path : nil
    case .mcp:
      return "MCP tool"
    default:
      return nil
    }
  }

  var body: some View {
    PanelScaffold(model: model, availableHeight: availableHeight) {
      VStack(alignment: .leading, spacing: PanelMetrics.sectionSpacing) {
        Text(title)
          .font(PanelTypography.title)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(subtitle)
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        bodyContent
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } footer: {
      footer
    }
    .onAppear {
      model.keyHandler = PanelKeyHandler(uses: usesKey, perform: handleKey)
      if !prompt.suggestions.isEmpty, model.dropdown.takeRequest(for: .approve) {
        toggleApproveDropdown()
      }
    }
  }

  private func toggleApproveDropdown() {
    let suggestions = prompt.suggestions
    let suggestionRows = suggestions.map { suggestion in
      let text = PermissionSuggestionText(suggestion)
      return PanelDropdownRow(title: text.title, detail: text.detail)
    }
    let menu = PanelDropdownMenu(
      id: .approve, direction: .up,
      rows: [PanelDropdownRow(title: "Allow once")] + suggestionRows
    ) { [model] row in
      guard row > 0 else {
        model.finish(.allowAsIs)
        return
      }
      guard suggestions.indices.contains(row - 1) else { return }
      model.finish(.allow(updatedInput: nil, updatedPermissions: [suggestions[row - 1].raw]))
    }
    model.dropdown.toggle(menu)
  }

  private func usesKey(_ key: PanelKey) -> Bool {
    switch key {
    case .primary: return true
    case .alternate:
      return footerState == .deny ? host.supportsInterrupt : !prompt.suggestions.isEmpty
    case .secondary: return footerState == .default
    case .digit, .left, .right, .up, .down: return false
    }
  }

  private func handleKey(_ key: PanelKey) {
    guard usesKey(key) else { return }
    switch key {
    case .primary:
      switch footerState {
      case .default:
        model.finish(.allowAsIs)
      case .deny:
        model.finish(.deny(reason: reasonText, interrupt: false))
      }
    case .alternate:
      switch footerState {
      case .deny:
        model.finish(.deny(reason: reasonText, interrupt: true))
      case .default:
        toggleApproveDropdown()
      }
    case .secondary:
      footerState = .deny
    case .digit, .left, .right, .up, .down:
      break
    }
  }

  @ViewBuilder
  private var bodyContent: some View {
    switch prompt.body {
    case .bash(let command, _):
      bashBody(command: command)
    case .edit, .write, .patch:
      if let fileDiffs {
        loadedFileDiffsView(fileDiffs)
      } else {
        fallbackBody
      }
    case .webFetch(let url, let webFetchPrompt):
      webFetchBody(url: url, prompt: webFetchPrompt)
    case .mcp(_, _, let arguments):
      jsonCard(arguments)
    case .json(let value):
      jsonCard(value)
    }
  }

  private func bashBody(command: String) -> some View {
    CodeCard {
      Text(highlighted(command))
        .font(.system(size: 12.5, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func highlighted(_ command: String) -> AttributedString {
    var attributed = AttributedString(command)
    for token in CommandHighlighter.tokens(in: command) {
      guard let range = Range(token.range, in: attributed) else { continue }
      attributed[range].foregroundColor = color(for: token.kind)
    }
    return attributed
  }

  private func color(for kind: ShellTokenKind) -> Color {
    switch kind {
    case .command: return .purple
    case .flag: return .orange
    case .string: return .green
    case .variable: return .teal
    case .operator: return .pink
    case .comment: return .secondary
    }
  }

  private func webFetchBody(url: String, prompt: String?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      CodeCard {
        Text(url)
          .font(.system(size: 12, design: .monospaced))
          .fixedSize(horizontal: false, vertical: true)
      }
      if let prompt {
        Text(prompt)
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func jsonCard(_ value: JSONValue) -> some View {
    CodeCard {
      Text(value.prettyPrinted)
        .font(.system(size: 12, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func loadedFileDiffsView(_ diffs: [FileDiff]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(diffs.enumerated()), id: \.offset) { _, diff in
        VStack(alignment: .leading, spacing: 6) {
          fileHeaderRow(diff)
          NumberedDiffCard(segments: diff.segments)
        }
      }
    }
  }

  private func fileHeaderRow(_ diff: FileDiff) -> some View {
    HStack(spacing: 8) {
      Chip(statusChipText(diff.status))
      Text(diff.displayPath)
        .font(.system(size: 12, design: .monospaced))
    }
  }

  private func statusChipText(_ status: FileDiffStatus) -> String {
    switch status {
    case .modified: return "Modified"
    case .created: return "Created"
    case .deleted: return "Deleted"
    case .moved(let to): return "Moved → \(to)"
    }
  }

  @ViewBuilder
  private var fallbackBody: some View {
    switch prompt.body {
    case .edit(_, let oldString, let newString, _):
      VStack(alignment: .leading, spacing: 6) {
        UnnumberedDiffCard(lines: PatchParser.diff(old: oldString, new: newString))
        fallbackCaption
      }
    case .write(_, let content):
      writeFallbackBody(content: content)
    case .patch(let text):
      patchFallbackBody(text: text)
    default:
      EmptyView()
    }
  }

  private func writeFallbackBody(content: String) -> some View {
    let preview = PatchParser.preview(of: content, lineLimit: 40)
    return VStack(alignment: .leading, spacing: 6) {
      UnnumberedDiffCard(lines: preview.lines.map { DiffLine(kind: .context, text: $0) })
      if preview.remaining > 0 {
        Text("… \(preview.remaining) more lines")
          .font(PanelTypography.secondary)
          .italic()
          .foregroundStyle(.secondary)
      }
      fallbackCaption
    }
  }

  private func patchFallbackBody(text: String) -> some View {
    let files = PatchParser.files(inApplyPatch: text)
    return VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(files.enumerated()), id: \.offset) { _, file in
        VStack(alignment: .leading, spacing: 6) {
          patchFileHeaderRow(file)
          UnnumberedDiffCard(lines: file.lines)
        }
      }
      fallbackCaption
    }
  }

  private func patchFileHeaderRow(_ file: PatchFile) -> some View {
    HStack(spacing: 8) {
      Chip(operationText(file.operation))
      Text(file.path)
        .font(.system(size: 12, design: .monospaced))
      if let movedTo = file.movedTo, movedTo != file.path {
        Text("→ \(movedTo)")
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func operationText(_ operation: PatchOperation) -> String {
    switch operation {
    case .add: return "Add"
    case .update: return "Update"
    case .delete: return "Delete"
    }
  }

  private var fallbackCaption: some View {
    Text("Showing the change only — the file couldn't be read.")
      .font(PanelTypography.secondary)
      .foregroundStyle(.secondary)
  }

  private var footer: some View {
    ZStack(alignment: .bottom) {
      defaultFooter
        .opacity(footerState == .default ? 1 : 0)
        .allowsHitTesting(footerState == .default)
        .accessibilityHidden(footerState != .default)
      denyFooter
        .opacity(footerState == .deny ? 1 : 0)
        .allowsHitTesting(footerState == .deny)
        .accessibilityHidden(footerState != .deny)
    }
    .onChange(of: footerState) { _, newState in
      isReasonFieldFocused = newState == .deny
    }
  }

  private var defaultFooter: some View {
    HStack {
      AnswerInChatButton(model: model)

      Spacer()

      Button {
        footerState = .deny
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text("Deny")
            .keyHintTextGuide(capHeight: DestructiveButtonStyle.labelCapHeight)
          KeyHint("⌫", placement: .onDestructive)
            .keyHintGuide()
        }
      }
      .buttonStyle(DestructiveButtonStyle())
      .disabled(!model.isArmed)

      ApproveButtons(
        hasSuggestions: !prompt.suggestions.isEmpty,
        isEnabled: model.isArmed && footerState == .default,
        onAllowOnce: { model.finish(.allowAsIs) },
        onToggleDropdown: toggleApproveDropdown
      )
    }
  }

  private var denyFooter: some View {
    HStack(spacing: 8) {
      Button("← Back") {
        footerState = .default
      }
      .buttonStyle(LinkButtonStyle())
      .disabled(!model.isArmed)

      TextField(reasonPlaceholder, text: $reasonText, axis: .vertical)
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .font(PanelTypography.body)
        .padding(8)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.05))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .focused($isReasonFieldFocused)
        .disabled(footerState != .deny)

      if host.supportsInterrupt {
        Button {
          model.finish(.deny(reason: reasonText, interrupt: true))
        } label: {
          HStack(alignment: .keyHintMidline, spacing: 4) {
            Text("Deny & stop")
              .keyHintTextGuide(capHeight: SecondaryButtonStyle.labelCapHeight)
            KeyHint("⌘⏎", placement: .onSecondary)
              .keyHintGuide()
          }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(!model.isArmed)
      }

      Button {
        model.finish(.deny(reason: reasonText, interrupt: false))
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text("Deny")
            .keyHintTextGuide(capHeight: DestructiveButtonStyle.labelCapHeight)
          KeyHint("⏎", placement: .onDestructive)
            .keyHintGuide()
        }
      }
      .buttonStyle(DestructiveButtonStyle())
      .disabled(!model.isArmed || footerState != .deny)
    }
  }
}

private struct ApproveButtons: View {
  let hasSuggestions: Bool
  let isEnabled: Bool
  let onAllowOnce: () -> Void
  let onToggleDropdown: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button {
        onAllowOnce()
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text("Approve")
            .keyHintTextGuide(capHeight: PrimaryButtonStyle.labelCapHeight)
          KeyHint("⏎", placement: .onAccent)
            .keyHintGuide()
        }
      }
      .buttonStyle(PrimaryButtonStyle())
      .disabled(!isEnabled)

      if hasSuggestions {
        Button(action: onToggleDropdown) {
          HStack(alignment: .keyHintMidline, spacing: 4) {
            Image(systemName: "chevron.down")
              .font(.system(size: 10, weight: .semibold))
              .keyHintTextGuide(capHeight: LinkButtonStyle.labelCapHeight)
            KeyHint("⌘⏎", placement: .link)
              .keyHintGuide()
          }
        }
        .buttonStyle(LinkButtonStyle())
        .panelDropdownAnchor(.approve)
        .disabled(!isEnabled)
      }
    }
  }
}
