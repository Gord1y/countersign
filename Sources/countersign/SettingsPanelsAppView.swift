import AppKit
import ApprovalCore
import SwiftUI

struct PanelsSection: View {
  let model: SettingsModel

  @FocusState private var isSnoozeFieldFocused: Bool

  var body: some View {
    SettingsSection(.panels) {
      ConfigProblemMessage(model: model)
      SettingsGroup {
        VStack(alignment: .leading, spacing: 0) {
          SameDelaysRow(model: model)
          if model.delaysPerAgent {
            SettingsDivider()
            DelayAgentRow(model: model)
          }
          SettingsDivider()
          PreferenceRow(.idleSeconds, model: model, problem: model.durationProblem(.idleSeconds)) {
            HStack(spacing: 6) {
              DurationField(name: .idleSeconds, model: model)
              Stepper(
                PreferenceName.idleSeconds.title,
                value: Binding(
                  get: { model.shownDelay(.idleSeconds) }, set: { model.setIdleSeconds($0) }),
                in: PreferenceRules.idleSecondsRange, step: 1
              )
              .labelsHidden()
              .controlSize(.small)
            }
          }
          SettingsDivider()
          PreferenceRow(
            .graceSeconds, model: model, problem: model.durationProblem(.graceSeconds)
          ) {
            HStack(spacing: 6) {
              DurationField(name: .graceSeconds, model: model)
              Stepper(
                PreferenceName.graceSeconds.title,
                value: Binding(
                  get: { model.shownDelay(.graceSeconds) }, set: { model.setGraceSeconds($0) }),
                in: PreferenceRules.graceSecondsRange, step: 1
              )
              .labelsHidden()
              .controlSize(.small)
            }
          }
          SettingsDivider()
          PreferenceRow(.armDelay, model: model, problem: model.durationProblem(.armDelay)) {
            DelaySlider(name: .armDelay, model: model, value: model.shownDelay(.armDelay)) {
              model.setArmDelay($0)
            }
          }
          SettingsDivider()
          PreferenceRow(
            .chainedArmDelay, model: model, problem: model.durationProblem(.chainedArmDelay)
          ) {
            DelaySlider(
              name: .chainedArmDelay, model: model, value: model.shownDelay(.chainedArmDelay)
            ) {
              model.setChainedArmDelay($0)
            }
          }
          SettingsDivider()
          PreferenceRow(
            .waitingNoticeMinutes, model: model,
            problem: model.durationProblem(.waitingNoticeMinutes)
          ) {
            DurationField(name: .waitingNoticeMinutes, model: model)
              .disabled(!model.waitingNotices)
          }
          SettingsDivider()
          PreferenceRow(
            .approvalCardDelay, model: model,
            problem: model.durationProblem(.approvalCardDelay)
          ) {
            DurationField(name: .approvalCardDelay, model: model)
              .disabled(!model.showsApprovalCardDelay)
          }
        }
        .disabled(model.configProblem != nil)
      }
      SettingsGroup {
        VStack(alignment: .leading, spacing: 0) {
          HandoffAppsRow(model: model)
          SettingsDivider()
          PreferenceRow(.snoozeMinutes, model: model, problem: model.snoozeProblem) {
            TextField(
              "1, 5, 15, 30",
              text: Binding(get: { model.snoozeText }, set: { model.setSnoozeText($0) })
            )
            .textFieldStyle(.roundedBorder)
            .font(PanelTypography.body.monospacedDigit())
            .frame(width: 150)
            .focused($isSnoozeFieldFocused)
            .onChange(of: isSnoozeFieldFocused) { _, focused in
              model.setEditingSnoozeMinutes(focused)
            }
            .onSubmit { model.commitSnoozeMinutes() }
            .onDisappear { model.setEditingSnoozeMinutes(false) }
          }
          SettingsDivider()
          QuietHoursRow(model: model)
          SettingsDivider()
          PreferenceRow(.questionNotes, model: model, problem: model.writeErrors[.questionNotes]) {
            SettingsSwitch(
              PreferenceName.questionNotes.title,
              isOn: Binding(get: { model.questionNotes }, set: { model.setQuestionNotes($0) }))
          }
          SettingsDivider()
          PreferenceRow(
            .modeAfterPlan, model: model, problem: model.writeErrors[.modeAfterPlan]
          ) {
            Picker(
              PreferenceName.modeAfterPlan.title,
              selection: Binding(
                get: { model.modeAfterPlan }, set: { model.setModeAfterPlan($0) })
            ) {
              ForEach(PlanApprovalMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
              }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
          }
          SettingsDivider()
          PreferenceRow(.panelSound, model: model, problem: model.writeErrors[.panelSound]) {
            HStack(spacing: 8) {
              Picker(
                PreferenceName.panelSound.title,
                selection: Binding(get: { model.panelSound }, set: { model.setPanelSound($0) })
              ) {
                ForEach(PanelSound.choices(installed: SystemSounds.installedNames), id: \.self) {
                  name in
                  Text(PanelSound.title(name)).tag(name)
                }
              }
              .pickerStyle(.menu)
              .controlSize(.small)
              .labelsHidden()
              .fixedSize()
              Button {
                SystemSounds.play(model.panelSound)
              } label: {
                Image(systemName: "speaker.wave.2")
              }
              .buttonStyle(.borderless)
              .foregroundStyle(.secondary)
              .disabled(PanelSound.isSilent(model.panelSound))
              .help("Play \(PanelSound.title(model.panelSound))")
              .accessibilityLabel("Play \(PanelSound.title(model.panelSound))")
            }
          }
          SettingsDivider()
          WaitingNoticesRow(model: model)
          SettingsDivider()
          ApprovalCardRow(model: model)
          SettingsDivider()
          ContextToggleRow(model: model)
        }
        .disabled(model.configProblem != nil)
        SettingsDivider()
        TestPanelRow(model: model)
        SettingsDivider()
        RestoreDefaultsRow(pane: .panels, model: model)
      }
    }
  }
}

private struct WaitingHookPromptPresenter: ViewModifier {
  let model: SettingsModel

  func body(content: Content) -> some View {
    content.onChange(of: model.waitingChange != nil) { _, isPending in
      guard isPending, let change = model.waitingChange else { return }
      WaitingHookPrompt.present(
        change: change, home: model.homeDirectory, on: NSApp.keyWindow,
        onConfirm: { model.confirmWaitingChange() },
        onCancel: { model.cancelWaitingChange() })
    }
  }
}

private struct SameDelaysPromptPresenter: ViewModifier {
  let model: SettingsModel

  func body(content: Content) -> some View {
    content.onChange(of: model.sameDelaysChange != nil) { _, isPending in
      guard isPending, let agents = model.sameDelaysChange else { return }
      SameDelaysPrompt.present(
        agents: agents, on: NSApp.keyWindow,
        onConfirm: { model.confirmSameDelays() },
        onCancel: { model.cancelSameDelays() })
    }
  }
}

private struct SameDelaysRow: View {
  let model: SettingsModel

  var body: some View {
    PreferenceRow(
      "Same delays for all agents", caption: "Off: pick an agent and give it its own delays."
    ) {
      SettingsSwitch(
        "Same delays for all agents",
        isOn: Binding(
          get: { !model.delaysPerAgent },
          set: { model.requestSameDelays($0) })
      )
    }
    .modifier(SameDelaysPromptPresenter(model: model))
  }
}

private struct DelayAgentRow: View {
  let model: SettingsModel

  var body: some View {
    PreferenceRow("Agent", caption: "The delays below apply to this agent.") {
      Picker(
        "Agent",
        selection: Binding(get: { model.delayAgent }, set: { model.setDelayAgent($0) })
      ) {
        ForEach(ApprovalCore.Host.allCases, id: \.self) { host in
          Text(host.displayName).tag(host)
        }
      }
      .pickerStyle(.segmented)
      .controlSize(.small)
      .labelsHidden()
      .fixedSize()
    }
  }
}

private struct ApprovalCardRow: View {
  let model: SettingsModel

  var body: some View {
    PreferenceRow(.approvalCard, model: model, problem: model.writeErrors[.approvalCard]) {
      EmptyView()
    } detail: {
      HStack(spacing: 16) {
        ForEach(ApprovalCore.Host.allCases, id: \.self) { host in
          Toggle(
            host.displayName,
            isOn: Binding(
              get: { model.approvalCardAgents.contains(host) },
              set: { model.setApprovalCard($0, for: host) })
          )
          .toggleStyle(.checkbox)
        }
      }
    }
  }
}

struct WaitingNoticesRow: View {
  let model: SettingsModel

  var body: some View {
    PreferenceRow(
      PreferenceName.waitingNotices.title, caption: PreferenceName.waitingNotices.caption,
      problem: model.waitingToggleProblem,
      explained: PreferenceRowExplanation(.waitingNotices)
    ) {
      SettingsSwitch(
        PreferenceName.waitingNotices.title,
        isOn: Binding(
          get: { model.waitingNotices },
          set: { model.requestWaitingNotices($0) })
      )
    }
    .modifier(WaitingHookPromptPresenter(model: model))
  }
}

struct AppSection: View {
  let model: SettingsModel

  var body: some View {
    SettingsSection(.app) {
      ConfigProblemMessage(model: model)
      SettingsGroup {
        LaunchAtLoginRow(model: model)
        SettingsDivider()
        VStack(alignment: .leading, spacing: 0) {
          PreferenceRow(
            .checkForUpdates, model: model, problem: model.writeErrors[.checkForUpdates]
          ) {
            SettingsSwitch(
              PreferenceName.checkForUpdates.title,
              isOn: Binding(
                get: { model.checkForUpdates }, set: { model.setCheckForUpdates($0) }))
          }
          SettingsDivider()
          PreferenceRow(.quitBehavior, model: model, problem: model.writeErrors[.quitBehavior]) {
            Picker(
              PreferenceName.quitBehavior.title,
              selection: Binding(get: { model.quitBehavior }, set: { model.setQuitBehavior($0) })
            ) {
              ForEach(QuitBehavior.allCases, id: \.self) { behavior in
                Text(behavior.title).tag(behavior)
              }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
          }
          SettingsDivider()
          PreferenceRow(.appearance, model: model, problem: model.writeErrors[.appearance]) {
            Picker(
              PreferenceName.appearance.title,
              selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })
            ) {
              ForEach(AppearanceChoice.allCases, id: \.self) { appearance in
                Text(appearance.title).tag(appearance)
              }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .fixedSize()
          }
          SettingsDivider()
          AccentColorRow(model: model)
        }
        .disabled(model.configProblem != nil)
        if model.appLinkOffer != nil || model.appLinkMessage != nil {
          SettingsDivider()
          AppLinkRow(model: model)
        }
        SettingsDivider()
        AppFooterRow(model: model)
      }
    }
  }
}

private struct AccentColorRow: View {
  static let customTitle = "Custom colour"

  let model: SettingsModel

  var body: some View {
    PreferenceRow(.accentColor, model: model, problem: model.writeErrors[.accentColor]) {
      HStack(spacing: 6) {
        ForEach(AccentPreset.allCases, id: \.self) { preset in
          AccentSwatch(preset: preset, isSelected: model.accentColor == preset.color) {
            model.setAccentColor(preset.color)
          }
        }
        ColorPicker(
          Self.customTitle,
          selection: Binding(
            get: { NSColor(model.accentColor).cgColor },
            set: { picked in
              if let color = Self.rgbColor(picked) {
                model.pickCustomAccentColor(color)
              }
            }),
          supportsOpacity: false
        )
        .labelsHidden()
        .help(Self.customTitle)
      }
    }
  }

  private static func rgbColor(_ picked: CGColor) -> HexColor? {
    guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
      let converted = picked.converted(to: sRGB, intent: .defaultIntent, options: nil),
      let components = converted.components, components.count >= 3
    else { return nil }
    return HexColor(
      red: channel(components[0]), green: channel(components[1]), blue: channel(components[2]))
  }

  private static func channel(_ value: CGFloat) -> UInt8 {
    UInt8((min(max(value, 0), 1) * 255).rounded())
  }
}

private struct AccentSwatch: View {
  let preset: AccentPreset
  let isSelected: Bool
  let choose: () -> Void

  var body: some View {
    Button(action: choose) {
      Circle()
        .fill(Color(nsColor: NSColor(preset.color)))
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        .frame(width: 16, height: 16)
        .padding(3)
        .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.85 : 0), lineWidth: 2))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(preset.title)
    .accessibilityLabel(preset.title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

struct ConfigProblemMessage: View {
  let model: SettingsModel

  var body: some View {
    if let problem = model.configProblem {
      InlineMessage("config.json can't be edited here: \(problem)", tone: .problem)
    }
  }
}

struct PreferenceRowReset {
  let name: PreferenceName
  let model: SettingsModel
}

struct PreferenceRowExplanation {
  let title: String
  let explanation: String
  let defaultText: String

  init(title: String, explanation: String, defaultText: String) {
    self.title = title
    self.explanation = explanation
    self.defaultText = defaultText
  }

  init(_ name: PreferenceName) {
    self.init(title: name.title, explanation: name.explanation, defaultText: name.defaultText)
  }
}

struct PreferenceRow<Control: View, Detail: View>: View {
  let title: String
  let caption: String
  let problem: String?
  let control: Control
  let detail: Detail
  let reset: PreferenceRowReset?
  let explained: PreferenceRowExplanation?

  init(
    _ title: String, caption: String, problem: String? = nil,
    explained: PreferenceRowExplanation? = nil,
    @ViewBuilder control: () -> Control, @ViewBuilder detail: () -> Detail
  ) {
    self.title = title
    self.caption = caption
    self.problem = problem
    self.control = control()
    self.detail = detail()
    self.reset = nil
    self.explained = explained
  }

  init(
    _ name: PreferenceName, model: SettingsModel, problem: String?, captionSuffix: String = "",
    @ViewBuilder control: () -> Control, @ViewBuilder detail: () -> Detail
  ) {
    self.title = name.title
    self.caption = name.caption + captionSuffix
    self.problem = problem
    self.control = control()
    self.detail = detail()
    self.reset = PreferenceRowReset(name: name, model: model)
    self.explained = PreferenceRowExplanation(name)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 4) {
            Text(title)
              .font(PanelTypography.body)
            if let explained {
              SettingsInfoButton(
                title: explained.title, explanation: explained.explanation,
                defaultText: explained.defaultText)
            }
          }
          Text(caption)
            .font(PanelTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
        .settingsHelp(explained?.explanation)
        Spacer(minLength: 16)
        if let reset, reset.model.isResettable(reset.name) {
          PreferenceResetButton(name: reset.name, model: reset.model)
        }
        control
      }
      detail
      if let problem {
        InlineMessage(problem, tone: .problem)
      }
    }
    .padding(.horizontal, SettingsMetrics.rowPadding)
    .padding(.vertical, 11)
  }
}

extension PreferenceRow where Detail == EmptyView {
  init(
    _ title: String, caption: String, problem: String? = nil,
    explained: PreferenceRowExplanation? = nil,
    @ViewBuilder control: () -> Control
  ) {
    self.init(
      title, caption: caption, problem: problem, explained: explained, control: control,
      detail: { EmptyView() })
  }

  init(
    _ name: PreferenceName, model: SettingsModel, problem: String?,
    @ViewBuilder control: () -> Control
  ) {
    self.init(name, model: model, problem: problem, control: control, detail: { EmptyView() })
  }
}

private struct PreferenceResetButton: View {
  let name: PreferenceName
  let model: SettingsModel

  var body: some View {
    Button {
      model.reset(name)
    } label: {
      Image(systemName: "arrow.uturn.backward")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .help(model.resetHelp(name))
    .accessibilityLabel(model.resetAccessibilityLabel(name))
  }
}

struct SettingsExplanationView: View {
  let explanation: String
  let defaultText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(explanation)
        .font(PanelTypography.body)
        .fixedSize(horizontal: false, vertical: true)
      Text("Default: \(defaultText)")
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
    }
    .padding(14)
    .frame(width: 260, alignment: .leading)
  }
}

private struct SettingsInfoButton: View {
  let title: String
  let explanation: String
  let defaultText: String

  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Image(systemName: "info.circle")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
    .accessibilityLabel("About \(title)")
    .popover(isPresented: $isPresented) {
      SettingsExplanationView(explanation: explanation, defaultText: defaultText)
    }
  }
}

extension View {
  @ViewBuilder
  fileprivate func settingsHelp(_ text: String?) -> some View {
    if let text {
      self.help(text)
    } else {
      self
    }
  }
}

struct RestoreDefaultsButton: View {
  let pane: SettingsPane
  let model: SettingsModel

  var body: some View {
    Button("Restore Defaults") {
      RestoreDefaultsPrompt.present(
        pane: pane, lines: model.restoreDefaultsConfirmationLines(for: pane),
        on: NSApp.keyWindow
      ) {
        model.resetGroup(pane.preferenceNames)
      }
    }
    .buttonStyle(SecondaryButtonStyle())
    .disabled(model.changedNames(in: pane.preferenceNames).isEmpty)
  }
}

struct RestoreDefaultsRow: View {
  let pane: SettingsPane
  let model: SettingsModel

  var body: some View {
    HStack(spacing: 0) {
      Spacer(minLength: 0)
      RestoreDefaultsButton(pane: pane, model: model)
    }
    .padding(.horizontal, SettingsMetrics.rowPadding)
    .padding(.vertical, 11)
  }
}

private struct AppFooterRow: View {
  let model: SettingsModel

  var body: some View {
    HStack(spacing: 8) {
      Button("Advanced…") { model.select(.advanced) }
        .buttonStyle(SecondaryButtonStyle())
      Spacer(minLength: 8)
      RestoreDefaultsButton(pane: .app, model: model)
    }
    .padding(.horizontal, SettingsMetrics.rowPadding)
    .padding(.vertical, 11)
  }
}

struct SettingsSwitch: View {
  let title: String
  let isOn: Binding<Bool>

  init(_ title: String, isOn: Binding<Bool>) {
    self.title = title
    self.isOn = isOn
  }

  var body: some View {
    Toggle(title, isOn: isOn)
      .toggleStyle(.switch)
      .controlSize(.small)
      .labelsHidden()
  }
}

struct ValueText: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(PanelTypography.body.monospacedDigit())
      .foregroundStyle(.secondary)
      .frame(width: 44, alignment: .trailing)
  }
}

private struct DurationField: View {
  let name: PreferenceName
  let model: SettingsModel
  var shownText: String?

  @FocusState private var isFocused: Bool

  var body: some View {
    TextField(
      name.title,
      text: Binding(
        get: { shownText ?? model.durationText(name) },
        set: { model.setDurationText($0, for: name) }),
      prompt: Text(model.durationPlaceholder(name))
    )
    .textFieldStyle(.roundedBorder)
    .labelsHidden()
    .font(PanelTypography.body.monospacedDigit())
    .multilineTextAlignment(.trailing)
    .frame(width: 72)
    .focused($isFocused)
    .onChange(of: isFocused) { _, focused in
      guard !focused else { return }
      model.commitDuration(name)
    }
    .onSubmit { model.commitDuration(name) }
  }
}

private struct DelaySlider: View {
  let name: PreferenceName
  let model: SettingsModel
  let value: Double
  let commit: (Double) -> Void

  @State private var isDragging = false
  @State private var draggedValue: Double?

  var body: some View {
    HStack(spacing: 10) {
      Slider(
        value: Binding(get: { shownValue }, set: { change($0) }),
        in: PreferenceRules.armDelayRange,
        onEditingChanged: { editingChanged($0) }
      )
      .controlSize(.small)
      .frame(width: 150)
      .accessibilityLabel(name.title)
      .accessibilityValue(PreferenceRules.secondsText(shownValue))
      DurationField(
        name: name, model: model,
        shownText: draggedValue.map { DurationText.compact($0) })
    }
  }

  private var shownValue: Double {
    draggedValue ?? value
  }

  private func change(_ newValue: Double) {
    let rounded = PreferenceRules.sliderArmDelay(newValue)
    guard isDragging else {
      commit(rounded)
      return
    }
    draggedValue = rounded
  }

  private func editingChanged(_ editing: Bool) {
    isDragging = editing
    guard !editing, let draggedValue else { return }
    self.draggedValue = nil
    commit(draggedValue)
  }
}

private struct QuietHoursRow: View {
  let model: SettingsModel

  var body: some View {
    PreferenceRow(.quietHours, model: model, problem: model.quietHoursProblem) {
      EmptyView()
    } detail: {
      VStack(alignment: .leading, spacing: 8) {
        if !model.quietHours.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(model.quietHours, id: \.self) { window in
              HStack(spacing: 8) {
                Text(window.title)
                  .font(PanelTypography.body.monospacedDigit())
                  .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                  model.removeQuietWindow(window)
                } label: {
                  Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(window.title)")
                .accessibilityLabel("Remove \(window.title)")
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
          HStack(spacing: 4) {
            ForEach(QuietWeekday.allCases, id: \.self) { day in
              QuietDayToggle(day: day, isOn: model.newQuietDays.contains(day)) {
                model.toggleNewQuietDay(day)
              }
            }
          }
          TextField(
            "19:00",
            text: Binding(get: { model.newQuietFrom }, set: { model.setNewQuietFrom($0) })
          )
          .textFieldStyle(.roundedBorder)
          .font(PanelTypography.body.monospacedDigit())
          .frame(width: 70)
          .onSubmit { model.addQuietWindow() }
          Text("to")
            .font(PanelTypography.caption)
            .foregroundStyle(.secondary)
          TextField(
            "09:00",
            text: Binding(get: { model.newQuietTo }, set: { model.setNewQuietTo($0) })
          )
          .textFieldStyle(.roundedBorder)
          .font(PanelTypography.body.monospacedDigit())
          .frame(width: 70)
          .onSubmit { model.addQuietWindow() }
          Button("Add") { model.addQuietWindow() }
            .buttonStyle(SecondaryButtonStyle())
        }
      }
    }
  }
}

private struct QuietDayToggle: View {
  let day: QuietWeekday
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(day.initial)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .frame(width: 26, height: 26)
        .background(
          Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
        )
    }
    .buttonStyle(.plain)
    .help(day.title)
    .accessibilityLabel(day.title)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

private struct HandoffAppsRow: View {
  let model: SettingsModel

  @FocusState private var isNewAppFieldFocused: Bool

  var body: some View {
    PreferenceRow(.handoffApps, model: model, problem: model.handoffProblem) {
      EmptyView()
    } detail: {
      VStack(alignment: .leading, spacing: 8) {
        if !model.handoffApps.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(model.handoffApps, id: \.self) { bundleID in
              HStack(spacing: 8) {
                Text(bundleID)
                  .font(PanelTypography.code)
                  .textSelection(.enabled)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Spacer(minLength: 8)
                Button {
                  model.removeHandoffApp(bundleID)
                } label: {
                  Image(systemName: "minus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(bundleID)")
                .accessibilityLabel("Remove \(bundleID)")
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
            "com.example.app",
            text: Binding(get: { model.newHandoffApp }, set: { model.setNewHandoffApp($0) })
          )
          .textFieldStyle(.roundedBorder)
          .font(PanelTypography.body)
          .focused($isNewAppFieldFocused)
          .onChange(of: isNewAppFieldFocused) { _, focused in
            if !focused {
              model.commitNewHandoffApp()
            }
          }
          .onSubmit { model.addHandoffApp() }
          .onDisappear { model.commitNewHandoffApp() }
          Button("Add") { model.addHandoffApp() }
            .buttonStyle(SecondaryButtonStyle())
        }
      }
    }
  }
}

private struct TestPanelRow: View {
  static let title = "Show a test panel"
  static let caption = "See your settings in a real panel, right away. Nothing reaches an agent."

  let model: SettingsModel

  var body: some View {
    PreferenceRow(Self.title, caption: Self.caption, problem: model.testPanelError) {
      HStack(spacing: 8) {
        ForEach(TestPanelKind.panelsTabKinds, id: \.self) { kind in
          Button(kind.title) { model.showTestPanel(kind) }
            .buttonStyle(SecondaryButtonStyle())
            .help(
              model.isTestPanelRunning
                ? "Bring back the test panel" : "Show a \(kind.rawValue) test panel")
        }
      }
      .fixedSize()
    }
  }
}

private struct LaunchAtLoginRow: View {
  static let title = "Launch at login"
  static let explanation =
    "Starts Countersign.app in the menu bar when you log in, so its status, Pause and Snooze are"
    + " there without opening it yourself. Panels appear either way: each agent's hook shows them,"
    + " with or without the menu-bar app. macOS keeps this as a login item, separate from"
    + " config.json, so Restore Defaults leaves it alone."
  static let defaultText = "Off"

  let model: SettingsModel

  var body: some View {
    PreferenceRow(
      Self.title, caption: caption, problem: model.launchAtLoginError,
      explained: PreferenceRowExplanation(
        title: Self.title, explanation: Self.explanation, defaultText: Self.defaultText)
    ) {
      HStack(spacing: 10) {
        if model.launchAtLogin == .requiresApproval {
          Button("Approve in System Settings") { model.approveLaunchAtLogin() }
            .buttonStyle(LinkButtonStyle())
        }
        SettingsSwitch(
          "Launch at login",
          isOn: Binding(get: { isOn }, set: { model.setLaunchAtLogin($0) })
        )
        .disabled(!isAvailable)
      }
    }
  }

  private var isOn: Bool {
    model.launchAtLogin == .enabled || model.launchAtLogin == .requiresApproval
  }

  private var isAvailable: Bool {
    model.launchAtLoginAvailable && model.launchAtLogin != .unavailable
  }

  private var caption: String {
    guard model.launchAtLoginAvailable else { return "Available in Countersign.app" }
    guard model.launchAtLogin != .unavailable else { return "Unavailable for this copy of the app" }
    return "Start the menu-bar app when you log in. macOS keeps this one, not config.json."
  }
}

private struct AppLinkRow: View {
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: "app.badge")
          .font(.system(size: 15))
          .foregroundStyle(.secondary)
          .frame(width: SettingsMetrics.glyphWidth)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(AppBundleLink.bundleName)
            .font(.system(size: 13, weight: .semibold))
          Text("Found next to this countersign binary.")
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 12)
        if model.appLinkOffer != nil {
          Button("Link Countersign.app into ~/Applications") { model.linkApp() }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
        }
      }
      if let message = model.appLinkMessage {
        InlineMessage(message, tone: model.appLinkFailed ? .problem : .done)
          .padding(.leading, SettingsMetrics.glyphWidth + 10)
      }
    }
    .padding(SettingsMetrics.rowPadding)
  }
}
