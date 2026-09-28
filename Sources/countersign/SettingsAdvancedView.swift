import AppKit
import ApprovalCore
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSection: View {
  let model: SettingsModel

  var body: some View {
    SettingsSection(.advanced) {
      Button("‹ App") { model.select(.app) }
        .buttonStyle(.plain)
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
      SettingsGroup {
        VStack(alignment: .leading, spacing: 10) {
          Text((model.configPath as NSString).abbreviatingWithTildeInPath)
            .font(PanelTypography.code)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(model.configPath)
          HStack(spacing: 8) {
            Button("Open in Editor") { model.openConfigInEditor() }
              .buttonStyle(SecondaryButtonStyle())
            Button(model.copied == .path ? "Copied" : "Copy Path") { model.copy(.path) }
              .buttonStyle(SecondaryButtonStyle())
            Spacer(minLength: 0)
          }
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Schema")
              .font(PanelTypography.secondary)
              .foregroundStyle(.secondary)
            if let schema = URL(string: SettingsPrompt.schemaURL) {
              Link(destination: schema) {
                Text(SettingsPrompt.schemaURL)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              .font(PanelTypography.secondary)
              .help(SettingsPrompt.schemaURL)
            }
          }
          Text(PreferenceOverrides.fileOnlyNote)
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if let error = model.editorOpenProblem(at: .advanced) {
            InlineMessage(error, tone: .problem)
          }
        }
        .padding(SettingsMetrics.rowPadding)
        SettingsDivider()
        PreferenceRow(.editorApp, model: model, problem: nil) {
          EditorAppMenu(model: model)
        }
        SettingsDivider()
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Ask your coding agent")
                .font(PanelTypography.body)
              Text(
                "Fill in what you want and send it to Claude Code, Codex, Cursor or Antigravity."
              )
              .font(PanelTypography.caption)
              .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(model.copied == .prompt ? "Copied" : "Copy") { model.copy(.prompt) }
              .buttonStyle(SecondaryButtonStyle())
          }
          CodeCard {
            Text(model.prompt)
              .font(PanelTypography.code)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(SettingsMetrics.rowPadding)
      }
    }
  }
}

private struct EditorAppOption: Identifiable {
  let id: String
  let name: String
  let icon: NSImage
}

private struct EditorAppMenu: View {
  let model: SettingsModel

  var body: some View {
    Menu {
      Button(defaultAppLabel) { model.reset(.editorApp) }
      ForEach(installedApps) { app in
        Button {
          model.setEditorApp(app.id)
        } label: {
          Label {
            Text(app.name)
          } icon: {
            Image(nsImage: app.icon)
          }
        }
      }
      Divider()
      Button("Other…") { chooseOtherApp() }
    } label: {
      Text(menuTitle)
    }
    .controlSize(.small)
    .fixedSize()
  }

  private var defaultAppLabel: String {
    guard let name = defaultAppName else { return PreferenceName.editorApp.defaultText }
    return "Default app (\(name))"
  }

  private var defaultAppName: String? {
    guard let url = NSWorkspace.shared.urlForApplication(toOpen: model.configFile) else {
      return nil
    }
    return FileManager.default.displayName(atPath: url.path)
  }

  private var installedApps: [EditorAppOption] {
    NSWorkspace.shared.urlsForApplications(toOpen: model.configFile).compactMap { url in
      guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
      return EditorAppOption(
        id: bundleID, name: FileManager.default.displayName(atPath: url.path),
        icon: NSWorkspace.shared.icon(forFile: url.path))
    }
  }

  private var menuTitle: String {
    guard let bundleID = model.editorApp else { return defaultAppLabel }
    if let match = installedApps.first(where: { $0.id == bundleID }) {
      return match.name
    }
    return bundleID
  }

  private func chooseOtherApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url,
      let bundleID = Bundle(url: url)?.bundleIdentifier
    else { return }
    model.setEditorApp(bundleID)
  }
}
