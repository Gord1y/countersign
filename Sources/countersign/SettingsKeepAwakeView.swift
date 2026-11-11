import AppKit
import ApprovalCore
import SwiftUI

enum KeepAwakeBlockMode: Equatable {
  case live
  case off
  case on(KeepAwakeState)
  case appOnly
  case broken
}

struct KeepAwakeBlock: View {
  static let title = "Keep Mac awake"
  static let onCaption = "Adds Keep Mac Awake to the menu bar menu. Start it there or below."
  static let appOnlyCaption = "Available in Countersign.app"

  let model: SettingsModel
  var mode: KeepAwakeBlockMode = .live

  var body: some View {
    SettingsBlock(Self.title) {
      VStack(alignment: .leading, spacing: 0) {
        switchRow
        if showsDetails {
          SettingsDivider()
          durationRow
          SettingsDivider()
          cutoffRow
          SettingsDivider()
          statusRow
        }
      }
      .disabled(isDisabled)
    }
  }

  private var resolvedMode: KeepAwakeBlockMode {
    guard mode == .live else { return mode }
    guard model.launchAtLoginAvailable else { return .appOnly }
    return model.keepAwake ? .on(.notRunning) : .off
  }

  private var isDisabled: Bool {
    switch resolvedMode {
    case .appOnly, .broken: return true
    case .live, .off, .on: return mode == .live && model.configProblem != nil
    }
  }

  private var isOn: Bool {
    if case .on = resolvedMode { return true }
    return false
  }

  private var showsDetails: Bool {
    isOn
  }

  private var caption: String {
    switch resolvedMode {
    case .appOnly: return Self.appOnlyCaption
    case .on: return Self.onCaption
    case .live, .off, .broken: return PreferenceName.keepAwake.caption
    }
  }

  private var switchRow: some View {
    PreferenceRow(
      Self.title, caption: caption, problem: model.writeErrors[.keepAwake],
      explained: PreferenceRowExplanation(.keepAwake)
    ) {
      SettingsSwitch(
        Self.title,
        isOn: Binding(
          get: { mode == .live ? model.keepAwake : isOn },
          set: { model.requestKeepAwake($0) })
      )
    }
  }

  private var durationRow: some View {
    PreferenceRow(
      .keepAwakeDuration, model: model, problem: model.writeErrors[.keepAwakeDuration]
    ) {
      Picker(
        PreferenceName.keepAwakeDuration.title,
        selection: Binding(
          get: { model.keepAwakeDuration }, set: { model.setKeepAwakeDuration($0) })
      ) {
        ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
          Text(duration.settingsTitle).tag(duration)
        }
      }
      .pickerStyle(.menu)
      .controlSize(.small)
      .labelsHidden()
      .fixedSize()
    }
  }

  private var cutoffRow: some View {
    PreferenceRow(
      .keepAwakeBatteryCutoff, model: model, problem: model.batteryCutoffProblem
    ) {
      HStack(spacing: 6) {
        BatteryCutoffField(model: model)
        Stepper(
          PreferenceName.keepAwakeBatteryCutoff.title,
          value: Binding(
            get: { model.keepAwakeBatteryCutoff }, set: { model.setKeepAwakeBatteryCutoff($0) }),
          in: Settings.keepAwakeBatteryCutoffRange, step: Settings.keepAwakeBatteryCutoffStep
        )
        .labelsHidden()
        .controlSize(.small)
      }
    }
  }

  @ViewBuilder
  private var statusRow: some View {
    if case .on(let fixed) = mode {
      KeepAwakeStatusRow(model: model, state: fixed)
    } else {
      TimelineView(.periodic(from: .now, by: 2)) { _ in
        KeepAwakeStatusRow(model: model, state: model.currentKeepAwakeState())
      }
    }
  }
}

private struct KeepAwakeStatusRow: View {
  let model: SettingsModel
  let state: KeepAwakeState

  var body: some View {
    PreferenceRow(state.statusTitle, caption: state.statusCaption()) {
      if state == .notRunning {
        Button("Start") { model.startKeepAwake() }
          .buttonStyle(SecondaryButtonStyle())
      } else {
        Button("Stop") { model.stopKeepAwake() }
          .buttonStyle(SecondaryButtonStyle())
      }
    }
  }
}

@MainActor
enum KeepAwakeSheet {
  static func present(model: SettingsModel, on window: NSWindow?) {
    guard let window else {
      model.cancelKeepAwake()
      return
    }
    let sheetWindow = SettingsSheetWindow()
    let finish = { [weak window, weak sheetWindow] in
      guard let window, let sheetWindow else { return }
      window.endSheet(sheetWindow)
      sheetWindow.contentViewController = nil
    }
    sheetWindow.contentViewController = NSHostingController(
      rootView: KeepAwakeSheetView(
        confirm: {
          model.confirmKeepAwake()
          finish()
        },
        cancel: {
          model.cancelKeepAwake()
          finish()
        }))
    window.beginSheet(sheetWindow) { _ in model.cancelKeepAwake() }
  }
}

struct KeepAwakeSheetView: View {
  static let width: CGFloat = 440
  static let title = "Turn on Keep Mac Awake?"
  static let cancelButton = "Cancel"
  static let confirmButton = "Turn On"
  static let facts: [KeepAwakeFact] = [
    KeepAwakeFact(
      symbol: "plus.circle", title: "What it adds",
      text:
        "A Keep Mac Awake item in the menu bar menu. Nothing holds the Mac awake until you start it."
    ),
    KeepAwakeFact(
      symbol: "shippingbox", title: "What it installs",
      text: "Nothing. No helper, login item, launch agent or administrator password."),
    KeepAwakeFact(
      symbol: "bolt", title: "While it runs",
      text:
        "The menu-bar app asks macOS to skip idle sleep, on battery down to your cutoff. An idle Mac uses more battery awake than asleep."
    ),
    KeepAwakeFact(
      symbol: "lock.display", title: "What stays the same",
      text: "The display still turns off and locks. Closing the lid still sleeps the Mac."),
    KeepAwakeFact(
      symbol: "stop.circle", title: "When it ends",
      text: "At its end time, when you stop it, when Countersign quits or when the Mac restarts."),
  ]

  let confirm: () -> Void
  let cancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(Self.title)
        .font(PanelTypography.title)
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Self.facts, id: \.title) { fact in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: fact.symbol)
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
              .frame(width: SettingsMetrics.glyphWidth)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(fact.title)
                .font(PanelTypography.body)
                .fontWeight(.semibold)
              Text(fact.text)
                .font(PanelTypography.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button(Self.cancelButton) { cancel() }
          .buttonStyle(SecondaryButtonStyle())
          .keyboardShortcut(.cancelAction)
          .fixedSize()
        Button(Self.confirmButton) { confirm() }
          .buttonStyle(PrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
          .fixedSize()
      }
    }
    .padding(20)
    .frame(width: Self.width, alignment: .leading)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

struct KeepAwakeFact {
  let symbol: String
  let title: String
  let text: String
}

private struct BatteryCutoffField: View {
  let model: SettingsModel

  @FocusState private var isFocused: Bool

  var body: some View {
    TextField(
      PreferenceName.keepAwakeBatteryCutoff.title,
      text: Binding(
        get: { model.shownBatteryCutoffText }, set: { model.setBatteryCutoffText($0) })
    )
    .textFieldStyle(.roundedBorder)
    .labelsHidden()
    .font(PanelTypography.body.monospacedDigit())
    .multilineTextAlignment(.trailing)
    .frame(width: 72)
    .focused($isFocused)
    .onChange(of: isFocused) { _, focused in
      guard !focused else { return }
      model.commitBatteryCutoff()
    }
    .onSubmit { model.commitBatteryCutoff() }
  }
}
