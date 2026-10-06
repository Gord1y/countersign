import AppKit
import ApprovalCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorAppOption: Identifiable {
  let id: String
  let name: String
  let icon: NSImage
}

enum EditorApps {
  static func installed(opening file: URL) -> [EditorAppOption] {
    NSWorkspace.shared.urlsForApplications(toOpen: file).compactMap { option(at: $0) }
  }

  static func defaultApp(opening file: URL) -> EditorAppOption? {
    NSWorkspace.shared.urlForApplication(toOpen: file).flatMap { option(at: $0) }
  }

  static func option(at url: URL) -> EditorAppOption? {
    guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
    return EditorAppOption(
      id: bundleID, name: name(of: url), icon: NSWorkspace.shared.icon(forFile: url.path))
  }

  static func name(of url: URL) -> String {
    let name = FileManager.default.displayName(atPath: url.path)
    let suffix = ".app"
    return name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
  }

  @MainActor
  static func pickApplication() -> EditorAppOption? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return option(at: url)
  }
}

struct EditorChoiceSheet: View {
  let choice: EditorChoice
  let configFile: URL
  let onOpen: (String, Bool) -> Void
  let onCancel: () -> Void

  @State private var apps: [EditorAppOption]
  @State private var defaultID: String?
  @State private var selection: String?
  @State private var always = true

  init(
    choice: EditorChoice, configFile: URL, onOpen: @escaping (String, Bool) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.choice = choice
    self.configFile = configFile
    self.onOpen = onOpen
    self.onCancel = onCancel
    let defaultApp = EditorApps.defaultApp(opening: configFile)
    var listed = EditorApps.installed(opening: configFile)
    if let defaultApp {
      listed.removeAll { $0.id == defaultApp.id }
      listed.insert(defaultApp, at: 0)
    }
    _apps = State(initialValue: listed)
    _defaultID = State(initialValue: defaultApp?.id)
    _selection = State(initialValue: nil)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Open config.json with")
        .font(PanelTypography.title)
      if let notice = choice.missingNotice {
        InlineMessage(notice, tone: .problem)
      }
      ScrollView {
        VStack(spacing: 0) {
          ForEach(apps) { app in
            row(app)
          }
        }
      }
      .frame(height: 220)
      .background(
        RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
          .strokeBorder(Color(nsColor: .separatorColor))
      )
      HStack {
        Button("Other…") { pickOther() }
          .buttonStyle(SecondaryButtonStyle())
        Spacer(minLength: 0)
      }
      Toggle("Always use this app", isOn: $always)
        .font(PanelTypography.body)
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button("Cancel") { onCancel() }
          .buttonStyle(SecondaryButtonStyle())
          .keyboardShortcut(.cancelAction)
        Button("Open") { openSelection() }
          .buttonStyle(PrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
          .disabled(selection == nil)
      }
    }
    .padding(20)
    .frame(width: 380)
  }

  private func row(_ app: EditorAppOption) -> some View {
    let isSelected = selection == app.id
    return HStack(spacing: 8) {
      Image(nsImage: app.icon)
        .resizable()
        .frame(width: 20, height: 20)
      Text(app.id == defaultID ? "\(app.name) (default)" : app.name)
        .font(PanelTypography.body)
        .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { onOpen(app.id, always) }
    .onTapGesture { selection = app.id }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func openSelection() {
    guard let selection else { return }
    onOpen(selection, always)
  }

  private func pickOther() {
    guard let picked = EditorApps.pickApplication() else { return }
    if !apps.contains(where: { $0.id == picked.id }) {
      apps.append(picked)
    }
    selection = picked.id
  }
}
