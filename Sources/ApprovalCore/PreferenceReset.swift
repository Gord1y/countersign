import Foundation

public enum PreferenceReset {
  public static let hostsNote =
    "Values set for one agent under hosts in config.json stay as they are."

  public static func isChanged(_ name: PreferenceName, in file: ConfigFile) -> Bool {
    switch name {
    case .armDelay:
      return changed(file.armDelay, from: Settings.defaultArmDelay)
    case .chainedArmDelay:
      return changed(file.chainedArmDelay, from: Settings.defaultChainedArmDelay)
    case .idleSeconds:
      return changed(file.idleSeconds, from: Settings.defaultIdleSeconds)
    case .graceSeconds:
      return changed(file.graceSeconds, from: Settings.defaultGraceSeconds)
    case .snoozeMinutes:
      return changed(file.snoozeMinutes, from: Settings.defaultSnoozeMinutes)
    case .handoffApps:
      return changed(file.handoffApps, from: Settings.defaultHandoffApps)
    case .checkForUpdates:
      return changed(file.checkForUpdates, from: Settings.defaultCheckForUpdates)
    case .quitBehavior:
      return changed(file.quitBehavior, from: Settings.defaultQuitBehavior)
    case .modeAfterPlan:
      return changed(file.modeAfterPlan, from: Settings.defaultModeAfterPlan)
    case .questionNotes:
      return changed(file.questionNotes, from: Settings.defaultQuestionNotes)
    case .appearance:
      return changed(file.appearance, from: Settings.defaultAppearance)
    case .accentColor:
      return changed(file.accentColor, from: Settings.defaultAccentColor)
    case .editorApp:
      return file.editorApp != nil
    case .contextCheckpointsEnabled:
      return changed(
        file.contextCheckpoints?.enabled, from: ContextCheckpointSettings.default.enabled)
    case .contextMode:
      return changed(file.contextCheckpoints?.mode, from: ContextCheckpointSettings.defaultMode)
    case .contextStandardThresholds:
      return changed(
        file.contextCheckpoints?.standardThresholds,
        from: ContextCheckpointSettings.defaultStandardThresholds)
    case .contextMillionThresholds:
      return changed(
        file.contextCheckpoints?.millionThresholds,
        from: ContextCheckpointSettings.defaultMillionThresholds)
    case .contextModelThresholds:
      return !(file.contextCheckpoints?.modelThresholds ?? [:]).isEmpty
    case .contextRearmBelow:
      return changed(
        file.contextCheckpoints?.rearmBelow, from: ContextCheckpointSettings.defaultRearmBelow)
    case .contextHandoffFile:
      return changed(
        file.contextCheckpoints?.handoffFile, from: ContextCheckpointSettings.defaultHandoffFile)
    case .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteCompact,
      .contextNoteHandoff:
      return changed(
        name.noteName.flatMap { file.contextCheckpoints?.notes[$0] },
        from: ContextCheckpointNotes.default.text(for: name) ?? "")
    case .contextMenuBarMeter:
      return changed(
        file.contextCheckpoints?.menuBarMeter, from: ContextCheckpointSettings.default.menuBarMeter)
    }
  }

  public static func changedNames(in file: ConfigFile, within names: [PreferenceName])
    -> [PreferenceName]
  {
    names.filter { isChanged($0, in: file) }
  }

  public static func hasHostValues(for names: [PreferenceName], in file: ConfigFile) -> Bool {
    let overrides = [file.claude, file.codex, file.cursor, file.antigravity].compactMap { $0 }
    return overrides.contains { block in names.contains { setsHostValue($0, in: block) } }
  }

  public static func confirmationLines(
    changed names: [PreferenceName], group: [PreferenceName], current: PreferenceValues,
    file: ConfigFile
  ) -> [String] {
    var lines = names.map { line(for: $0, current: current) }
    if hasHostValues(for: group, in: file) {
      lines.append(hostsNote)
    }
    return lines
  }

  static func line(for name: PreferenceName, current: PreferenceValues) -> String {
    "\(name.title): \(valueText(name, in: current)) → \(valueText(name, in: PreferenceValues()))"
  }

  public static func valueText(_ name: PreferenceName, in values: PreferenceValues) -> String {
    switch name {
    case .armDelay: return PreferenceRules.secondsText(values.armDelay)
    case .chainedArmDelay: return PreferenceRules.secondsText(values.chainedArmDelay)
    case .idleSeconds: return PreferenceRules.secondsText(values.idleSeconds)
    case .graceSeconds: return PreferenceRules.secondsText(values.graceSeconds)
    case .snoozeMinutes: return PreferenceRules.snoozeText(values.snoozeMinutes)
    case .handoffApps: return handoffAppsCountText(values.handoffApps.count)
    case .checkForUpdates: return values.checkForUpdates ? "On" : "Off"
    case .questionNotes: return values.questionNotes ? "On" : "Off"
    case .quitBehavior: return values.quitBehavior.title
    case .modeAfterPlan: return values.modeAfterPlan.title
    case .appearance: return values.appearance.title
    case .accentColor: return AccentPreset.name(of: values.accentColor)
    case .editorApp: return values.editorApp ?? PreferenceName.editorApp.defaultText
    case .contextCheckpointsEnabled: return values.contextCheckpoints.enabled ? "On" : "Off"
    case .contextMode: return values.contextCheckpoints.mode.rawValue.capitalized
    case .contextStandardThresholds: return ladderText(values.contextCheckpoints.standardThresholds)
    case .contextMillionThresholds: return ladderText(values.contextCheckpoints.millionThresholds)
    case .contextModelThresholds:
      return modelsCountText(values.contextCheckpoints.modelThresholds.count)
    case .contextRearmBelow: return percentText(values.contextCheckpoints.rearmBelow)
    case .contextHandoffFile: return values.contextCheckpoints.handoffFile
    case .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteCompact,
      .contextNoteHandoff:
      let text = values.contextCheckpoints.notes.text(for: name)
      return text == ContextCheckpointNotes.default.text(for: name) ? "Default" : "Custom"
    case .contextMenuBarMeter: return values.contextCheckpoints.menuBarMeter ? "On" : "Off"
    }
  }

  static func ladderText(_ ladder: [Int]) -> String {
    ladder.map(ContextCheckpointNotes.tokenText).joined(separator: ", ")
  }

  static func percentText(_ ratio: Double) -> String {
    "\(Int((ratio * 100).rounded()))%"
  }

  private static func modelsCountText(_ count: Int) -> String {
    guard count > 0 else { return "none" }
    return "\(count) model\(count == 1 ? "" : "s")"
  }

  private static func handoffAppsCountText(_ count: Int) -> String {
    guard count > 0 else { return "none" }
    return "\(count) app\(count == 1 ? "" : "s")"
  }

  private static func setsHostValue(_ name: PreferenceName, in overrides: ConfigFile.HostOverrides)
    -> Bool
  {
    switch name {
    case .armDelay: return overrides.armDelay != nil
    case .chainedArmDelay: return overrides.chainedArmDelay != nil
    case .idleSeconds: return overrides.idleSeconds != nil
    case .graceSeconds: return overrides.graceSeconds != nil
    case .snoozeMinutes: return overrides.snoozeMinutes != nil
    case .handoffApps: return overrides.handoffApps != nil
    case .checkForUpdates, .questionNotes, .quitBehavior, .modeAfterPlan, .appearance,
      .accentColor, .editorApp, .contextCheckpointsEnabled, .contextMode,
      .contextStandardThresholds, .contextMillionThresholds, .contextModelThresholds,
      .contextRearmBelow, .contextHandoffFile, .contextNoteSoft, .contextNoteStatus,
      .contextNoteInsist, .contextNoteCompact, .contextNoteHandoff, .contextMenuBarMeter:
      return false
    }
  }

  private static func changed<Value: Equatable>(_ value: Value?, from defaultValue: Value) -> Bool {
    guard let value else { return false }
    return value != defaultValue
  }
}
