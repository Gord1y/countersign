import Foundation

extension ConfigValue {
  public static func text(_ name: PreferenceName, values: PreferenceValues) -> String {
    let context = values.contextCheckpoints
    switch name {
    case .checkForUpdates: return flag(values.checkForUpdates)
    case .questionNotes: return flag(values.questionNotes)
    case .showSkills: return flag(values.showSkills)
    case .keepAwake: return flag(values.keepAwake)
    case .waitingNotices: return flag(values.waitingNotices)
    case .contextCheckpointsEnabled: return flag(context.enabled)
    case .contextMenuBarMeter: return flag(context.menuBarMeter)
    case .contextColdCacheCard: return flag(context.coldCacheCard)
    case .idleSeconds: return DurationText.compact(values.idleSeconds)
    case .graceSeconds: return DurationText.compact(values.graceSeconds)
    case .armDelay: return DurationText.compact(values.armDelay)
    case .chainedArmDelay: return DurationText.compact(values.chainedArmDelay)
    case .waitingNoticeDelay: return DurationText.compact(values.waitingNoticeDelay)
    case .waitingNoticeDuration: return DurationText.compact(values.waitingNoticeDuration)
    case .approvalCardDelay: return DurationText.compact(values.approvalCardDelay)
    case .snoozeMinutes: return PreferenceRules.snoozeText(values.snoozePresets)
    case .quietHours: return quietHoursText(values.quietHours)
    case .handoffApps: return listText(values.handoffApps)
    case .approvalCard: return listText(values.approvalCardAgents.map(\.rawValue))
    case .quitBehavior: return values.quitBehavior.rawValue
    case .modeAfterPlan: return values.modeAfterPlan.rawValue
    case .appearance: return values.appearance.rawValue
    case .keepAwakeDuration: return values.keepAwakeDuration.rawValue
    case .contextMode: return context.mode.rawValue
    case .panelSound: return values.panelSound
    case .accentColor: return values.accentColor.hex
    case .keepAwakeBatteryCutoff: return String(values.keepAwakeBatteryCutoff)
    case .editorApp: return values.editorApp ?? "none"
    case .contextStandardThresholds:
      return PreferenceRules.contextLadderText(context.standardThresholds)
    case .contextMillionThresholds:
      return PreferenceRules.contextLadderText(context.millionThresholds)
    case .contextModelThresholds: return modelThresholdsText(context.modelThresholds)
    case .contextRearmBelow: return PreferenceReset.percentText(context.rearmBelow)
    case .contextMaxCompactions: return String(context.maxCompactions)
    case .contextSoftChoices: return choicesText(context.choices.soft)
    case .contextStatusChoices: return choicesText(context.choices.status)
    case .contextInsistChoices: return choicesText(context.choices.insist)
    case .contextHandoffFile: return context.handoffFile
    case .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteStop,
      .contextNoteCompact, .contextNoteHandoff, .contextNoteLimit:
      return context.notes.text(for: name) ?? ""
    }
  }

  private static func flag(_ value: Bool) -> String {
    value ? "true" : "false"
  }

  private static func listText(_ items: [String]) -> String {
    items.isEmpty ? "none" : items.joined(separator: ", ")
  }

  private static func choicesText(_ choices: [ContextCheckpointChoice]) -> String {
    choices.map(\.configName).joined(separator: ", ")
  }

  private static func quietHoursText(_ windows: [QuietWindow]) -> String {
    guard !windows.isEmpty else { return "none" }
    return windows.map { window in
      let days = window.days.map(\.rawValue).joined(separator: ",")
      return "\(days) \(window.fromText)-\(window.toText)"
    }.joined(separator: "; ")
  }

  private static func modelThresholdsText(_ thresholds: [String: [Int]]) -> String {
    guard !thresholds.isEmpty else { return "none" }
    return thresholds.keys.sorted().compactMap { prefix in
      thresholds[prefix].map { "\(prefix)=\(PreferenceRules.contextLadderText($0))" }
    }.joined(separator: "; ")
  }
}
