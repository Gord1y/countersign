import AppKit
import ApprovalCore
import SwiftUI

struct ContextSection: View {
  let model: SettingsModel

  var body: some View {
    SettingsSection(.context) {
      ConfigProblemMessage(model: model)
      SettingsGroup {
        VStack(alignment: .leading, spacing: 0) {
          ContextHookRow(model: model)
          SettingsDivider()
          PreferenceRow(.contextMode, model: model, problem: model.writeErrors[.contextMode]) {
            Picker(
              PreferenceName.contextMode.title,
              selection: Binding(
                get: { model.contextCheckpoints.mode }, set: { model.setContextMode($0) })
            ) {
              ForEach(ContextCheckpointMode.allCases, id: \.self) { mode in
                Text(mode.rawValue.capitalized).tag(mode)
              }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
          }
          SettingsDivider()
          ContextLadderRow(
            name: .contextStandardThresholds, placeholder: "100, 130, 160", model: model)
          SettingsDivider()
          ContextLadderRow(
            name: .contextMillionThresholds, placeholder: "200, 300, 400", model: model)
          SettingsDivider()
          ContextModelsRow(model: model)
          SettingsDivider()
          PreferenceRow(
            .contextRearmBelow, model: model, problem: model.writeErrors[.contextRearmBelow]
          ) {
            ContextRearmSlider(value: model.contextCheckpoints.rearmBelow) {
              model.setContextRearmBelow($0)
            }
          }
          SettingsDivider()
          ContextHandoffFileRow(model: model)
          SettingsDivider()
          ContextNotesRow(model: model)
          SettingsDivider()
          PreferenceRow(
            .contextMenuBarMeter, model: model, problem: model.writeErrors[.contextMenuBarMeter]
          ) {
            SettingsSwitch(
              PreferenceName.contextMenuBarMeter.title,
              isOn: Binding(
                get: { model.contextCheckpoints.menuBarMeter },
                set: { model.setContextMenuBarMeter($0) }))
          }
        }
        .disabled(model.configProblem != nil)
        SettingsDivider()
        ContextTestPanelRow(model: model)
        SettingsDivider()
        RestoreDefaultsRow(pane: .context, model: model)
      }
    }
  }
}

private struct ContextHookPromptPresenter: ViewModifier {
  let model: SettingsModel
  let origin: ContextHookChangeOrigin

  func body(content: Content) -> some View {
    content.onChange(of: model.contextChange(for: origin) != nil) { _, isPending in
      guard isPending, let change = model.contextChange(for: origin) else { return }
      ContextHookPrompt.present(
        change: change, path: model.contextHookFileText ?? "Claude Code's settings",
        on: NSApp.keyWindow,
        onConfirm: { model.confirmContextChange() },
        onCancel: { model.cancelContextChange() })
    }
  }
}

extension View {
  fileprivate func presentsContextHookPrompt(
    model: SettingsModel, origin: ContextHookChangeOrigin
  ) -> some View {
    modifier(ContextHookPromptPresenter(model: model, origin: origin))
  }
}

struct ContextToggleRow: View {
  static let notInstalledCaption = "Claude Code isn't installed."

  let model: SettingsModel

  var body: some View {
    PreferenceRow(
      PreferenceName.contextCheckpointsEnabled.title, caption: caption,
      problem: model.contextToggleProblem,
      explained: PreferenceRowExplanation(.contextCheckpointsEnabled)
    ) {
      SettingsSwitch(
        PreferenceName.contextCheckpointsEnabled.title,
        isOn: Binding(
          get: { model.contextCheckpointsEnabled },
          set: { model.requestContextCheckpoints($0) })
      )
      .disabled(!model.claudeIsInstalled)
    }
    .presentsContextHookPrompt(model: model, origin: .toggle)
  }

  private var caption: String {
    model.claudeIsInstalled
      ? PreferenceName.contextCheckpointsEnabled.caption : Self.notInstalledCaption
  }
}

private struct ContextHookRow: View {
  static let title = "Claude Code hook"

  let model: SettingsModel

  var body: some View {
    PreferenceRow(Self.title, caption: caption, problem: problem) {
      HStack(spacing: 10) {
        Text(model.contextHookStatus.title)
          .font(PanelTypography.body)
          .foregroundStyle(.secondary)
        if offersUpdate {
          Button("Update") { model.requestContextHookUpdate() }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(model.contextChange != nil)
        }
      }
    }
    .presentsContextHookPrompt(model: model, origin: .hookStatus)
  }

  private var caption: String {
    "Countersign's UserPromptSubmit entry in \(model.contextHookFileText ?? "Claude Code's settings")."
  }

  private var offersUpdate: Bool {
    switch model.contextHookStatus {
    case .notWired, .needsUpdate: return model.claudeIsInstalled
    case .wired, .unusable: return false
    }
  }

  private var problem: String? {
    if let failure = model.contextHookProblem(for: .hookStatus) { return failure }
    if case .unusable(let reason) = model.contextHookStatus { return reason }
    return nil
  }
}

private struct ContextLadderRow: View {
  let name: PreferenceName
  let placeholder: String
  let model: SettingsModel

  @FocusState private var isFocused: Bool

  var body: some View {
    PreferenceRow(name, model: model, problem: model.contextProblem(name)) {
      HStack(spacing: 4) {
        TextField(
          placeholder,
          text: Binding(
            get: { model.contextText(for: name) }, set: { model.setContextText($0, for: name) })
        )
        .textFieldStyle(.roundedBorder)
        .font(PanelTypography.body.monospacedDigit())
        .frame(width: 150)
        .focused($isFocused)
        .onChange(of: isFocused) { _, focused in
          if !focused { model.commitContextText(name) }
        }
        .onSubmit { model.commitContextText(name) }
        .onDisappear { model.commitContextText(name) }
        Text("K")
          .font(PanelTypography.body)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct ContextModelsRow: View {
  let model: SettingsModel

  var body: some View {
    PreferenceRow(.contextModelThresholds, model: model, problem: model.contextModelProblem) {
      EmptyView()
    } detail: {
      VStack(alignment: .leading, spacing: 8) {
        if !model.contextModelThresholds.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(model.contextModelThresholds, id: \.prefix) { entry in
              HStack(spacing: 8) {
                Text("\(entry.prefix): \(ladderText(entry.ladder))")
                  .font(PanelTypography.code)
                  .textSelection(.enabled)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                  model.removeContextModel(entry.prefix)
                } label: {
                  Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(entry.prefix)")
                .accessibilityLabel("Remove \(entry.prefix)")
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .fill(Color.primary.opacity(0.05))
              )
            }
          }
        }
        HStack(spacing: 8) {
          TextField(
            "claude-opus-5",
            text: Binding(
              get: { model.newContextModelPrefix }, set: { model.setNewContextModelPrefix($0) })
          )
          .textFieldStyle(.roundedBorder)
          .font(PanelTypography.body)
          .onSubmit { model.addContextModel() }
          TextField(
            "250, 350, 450",
            text: Binding(
              get: { model.newContextModelLadder }, set: { model.setNewContextModelLadder($0) })
          )
          .textFieldStyle(.roundedBorder)
          .font(PanelTypography.body.monospacedDigit())
          .frame(width: 130)
          .onSubmit { model.addContextModel() }
          Text("K")
            .font(PanelTypography.body)
            .foregroundStyle(.secondary)
          Button("Add") { model.addContextModel() }
            .buttonStyle(SecondaryButtonStyle())
        }
      }
    }
  }

  private func ladderText(_ ladder: [Int]) -> String {
    ladder.map(ContextCheckpointNotes.tokenText).joined(separator: ", ")
  }
}

private struct ContextRearmSlider: View {
  let value: Double
  let commit: (Double) -> Void

  @State private var isDragging = false
  @State private var draggedPercent: Double?

  var body: some View {
    HStack(spacing: 10) {
      Slider(
        value: Binding(get: { shownPercent }, set: { change($0) }),
        in: PreferenceRules.contextRearmPercentRange,
        step: PreferenceRules.contextRearmPercentStep,
        onEditingChanged: { editingChanged($0) }
      )
      .controlSize(.small)
      .frame(width: 150)
      ValueText("\(Int(shownPercent))%")
    }
  }

  private var shownPercent: Double {
    draggedPercent ?? PreferenceRules.contextRearmPercent(value)
  }

  private func change(_ percent: Double) {
    guard isDragging else {
      commit(PreferenceRules.contextRearmBelow(percent: percent))
      return
    }
    draggedPercent = percent
  }

  private func editingChanged(_ editing: Bool) {
    isDragging = editing
    guard !editing, let draggedPercent else { return }
    self.draggedPercent = nil
    commit(PreferenceRules.contextRearmBelow(percent: draggedPercent))
  }
}

private struct ContextHandoffFileRow: View {
  let model: SettingsModel

  @FocusState private var isFocused: Bool

  var body: some View {
    PreferenceRow(
      .contextHandoffFile, model: model, problem: model.contextProblem(.contextHandoffFile)
    ) {
      TextField(
        ContextCheckpointSettings.defaultHandoffFile,
        text: Binding(
          get: { model.contextText(for: .contextHandoffFile) },
          set: { model.setContextText($0, for: .contextHandoffFile) })
      )
      .textFieldStyle(.roundedBorder)
      .font(PanelTypography.body)
      .frame(width: 220)
      .focused($isFocused)
      .onChange(of: isFocused) { _, focused in
        if !focused { model.commitContextText(.contextHandoffFile) }
      }
      .onSubmit { model.commitContextText(.contextHandoffFile) }
      .onDisappear { model.commitContextText(.contextHandoffFile) }
    }
  }
}

private struct ContextNotesRow: View {
  static let title = "Notes"
  static let caption = "What Countersign sends Claude at each checkpoint and after your choice."
  static let button = "Edit Notes…"

  let model: SettingsModel

  var body: some View {
    PreferenceRow(Self.title, caption: Self.caption) {
      Button(Self.button) {
        ContextNotesSheet.present(model: model, on: NSApp.keyWindow)
      }
      .buttonStyle(SecondaryButtonStyle())
    }
  }
}

private struct ContextTestPanelRow: View {
  static let title = "Try a checkpoint"
  static let caption =
    "See a context checkpoint panel right away. Nothing reaches an agent."
  static let button = "Show a context checkpoint"
  static let showing = "Showing a test panel…"

  let model: SettingsModel

  var body: some View {
    PreferenceRow(Self.title, caption: Self.caption, problem: model.testPanelError) {
      EmptyView()
    } detail: {
      HStack(spacing: 8) {
        Button(Self.button) { model.showTestPanel(.context) }
          .buttonStyle(SecondaryButtonStyle())
          .disabled(model.isTestPanelRunning)
        if model.isTestPanelRunning {
          Text(Self.showing)
            .font(PanelTypography.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
