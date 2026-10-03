import AppKit
import ApprovalCore
import SwiftUI

@MainActor
enum RuleSheet {
  static func present(model: SettingsModel, editing rule: ApprovalRule?, on window: NSWindow?) {
    guard let window else { return }
    let sheetWindow = NSWindow(
      contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    sheetWindow.isReleasedWhenClosed = false
    let hostingController = NSHostingController(
      rootView: RuleSheetView(
        model: model, editing: rule,
        close: { [weak window, weak sheetWindow] in
          guard let window, let sheetWindow else { return }
          window.endSheet(sheetWindow)
          sheetWindow.contentViewController = nil
        }))
    sheetWindow.contentViewController = hostingController
    window.beginSheet(sheetWindow)
  }

  static func chooseProject(home: URL) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = home
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return HomePath.abbreviating(url.path, relativeTo: home)
  }
}

struct RuleSheetView: View {
  static let width: CGFloat = 440
  static let labelWidth: CGFloat = 64
  static let newTitle = "New Rule"
  static let editTitle = "Edit Rule"
  static let addButton = "Add Rule"
  static let saveButton = "Save"
  static let toolCaption =
    "A tool name such as Bash, Shell or run_command; * matches anything, as in mcp__github__*."
  static let commandCaption =
    "A command prefix: git matches git status. Use base:args* for a wildcard, as in npm:install*."

  let model: SettingsModel
  let editing: ApprovalRule?
  let close: () -> Void

  @State private var draft: RuleDraft

  init(model: SettingsModel, editing: ApprovalRule?, close: @escaping () -> Void) {
    self.model = model
    self.editing = editing
    self.close = close
    _draft = State(initialValue: editing.map(RuleDraft.init(rule:)) ?? RuleDraft())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(editing == nil ? Self.newTitle : Self.editTitle)
        .font(PanelTypography.title)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
      VStack(alignment: .leading, spacing: 12) {
        field("Decision") {
          Picker("Decision", selection: $draft.decision) {
            Text("Allow").tag(ApprovalRule.Decision.allow)
            Text("Deny").tag(ApprovalRule.Decision.deny)
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .fixedSize()
        }
        field("Agent") {
          Picker("Agent", selection: $draft.agent) {
            Text("Any agent").tag(ApprovalCore.Host?.none)
            ForEach(ApprovalCore.Host.allCases, id: \.self) { host in
              Text(host.displayName).tag(ApprovalCore.Host?.some(host))
            }
          }
          .labelsHidden()
          .fixedSize()
        }
        field("Project") {
          HStack(spacing: 8) {
            TextField("Any project", text: $draft.project)
              .textFieldStyle(.roundedBorder)
            Button("Choose…") {
              if let path = RuleSheet.chooseProject(home: model.homeDirectory) {
                draft.project = path
              }
            }
            .buttonStyle(SecondaryButtonStyle())
          }
        }
        field("Tool", caption: Self.toolCaption) {
          TextField("Any tool", text: $draft.tool)
            .textFieldStyle(.roundedBorder)
        }
        field("Command", caption: Self.commandCaption) {
          TextField("Any command", text: $draft.command)
            .textFieldStyle(.roundedBorder)
            .font(PanelTypography.code)
        }
        if draft.decision == .deny {
          field("Message") {
            TextField(ApprovalRule.defaultDenyMessage, text: $draft.message)
              .textFieldStyle(.roundedBorder)
          }
        }
        ForEach(draft.problems, id: \.self) { problem in
          InlineMessage(problem, tone: .problem)
        }
        if let warning = draft.broadAllowWarning {
          InlineMessage(warning, tone: .warning)
        }
        if let error = model.rulesError {
          InlineMessage(error, tone: .problem)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 8)
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button("Cancel") { close() }
          .buttonStyle(SecondaryButtonStyle())
          .keyboardShortcut(.cancelAction)
        Button(editing == nil ? Self.addButton : Self.saveButton) { save() }
          .buttonStyle(PrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
          .disabled(!draft.problems.isEmpty)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(width: Self.width, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func field<Content: View>(
    _ label: String, caption: String? = nil, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(PanelTypography.body)
        .frame(width: Self.labelWidth, alignment: .leading)
      VStack(alignment: .leading, spacing: 4) {
        content()
        if let caption {
          Text(caption)
            .font(PanelTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func save() {
    guard let rule = draft.rule() else { return }
    let saved: Bool
    if let editing {
      saved = model.updateRule(old: editing, new: rule)
    } else {
      saved = model.addRule(rule)
    }
    if saved {
      close()
    }
  }
}
