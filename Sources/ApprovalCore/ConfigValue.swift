import Foundation

public enum ConfigValueError: Error, Sendable, Equatable, CustomStringConvertible {
  case refused(PreferenceName)
  case invalid(String)

  public var description: String {
    switch self {
    case .invalid(let message):
      return "error: \(message)"
    case .refused(let name):
      return
        "error: \(name.commandLineKey) can only be changed in Settings (\(name.title)):"
        + " \(ConfigValue.refusalReason(name))"
    }
  }
}

public enum ConfigValue {
  public static func refusal(_ name: PreferenceName) -> ConfigValueError? {
    switch name {
    case .keepAwake, .waitingNotices, .contextCheckpointsEnabled, .modeAfterPlan:
      return .refused(name)
    default: return nil
    }
  }

  public static func resetRefusal(_ name: PreferenceName) -> ConfigValueError? {
    switch name {
    case .waitingNotices, .contextCheckpointsEnabled: return .refused(name)
    default: return nil
    }
  }

  static func refusalReason(_ name: PreferenceName) -> String {
    switch name {
    case .keepAwake: return "it needs its explanation first"
    case .modeAfterPlan: return "it sets how much your agent may do after you approve a plan"
    default: return "it changes your agents' hook files"
    }
  }

  public static func edits(
    for name: PreferenceName, text: String, current: PreferenceValues
  ) -> Result<[PreferenceEdit], ConfigValueError> {
    if let refusal = refusal(name) { return .failure(refusal) }
    switch name {
    case .checkForUpdates: return boolean(text).map { [.checkForUpdates($0)] }
    case .questionNotes: return boolean(text).map { [.questionNotes($0)] }
    case .showSkills: return boolean(text).map { [.showSkills($0)] }
    case .contextMenuBarMeter: return boolean(text).map { [.contextMenuBarMeter($0)] }
    case .contextColdCacheCard: return boolean(text).map { [.contextColdCacheCard($0)] }
    case .idleSeconds:
      return duration(name, text).map { [.idleSeconds(PreferenceRules.idleSeconds($0))] }
    case .graceSeconds:
      return duration(name, text).map { [.graceSeconds(PreferenceRules.graceSeconds($0))] }
    case .armDelay: return duration(name, text).map { [.armDelay(PreferenceRules.armDelay($0))] }
    case .chainedArmDelay:
      return duration(name, text).map { [.chainedArmDelay(PreferenceRules.chainedArmDelay($0))] }
    case .waitingNoticeDelay: return duration(name, text).map { [.waitingNoticeDelay($0)] }
    case .waitingNoticeDuration: return duration(name, text).map { [.waitingNoticeDuration($0)] }
    case .approvalCardDelay: return duration(name, text).map { [.approvalCardDelay($0)] }
    case .snoozeMinutes:
      return PreferenceRules.snoozePresets(from: text).mapError(invalid).map {
        [.snoozePresets($0)]
      }
    case .quietHours: return quietWindows(text).map { [.quietHours($0)] }
    case .handoffApps:
      return handoffAppList(text).map { handoffEdits(listed: $0, current: current.handoffApps) }
    case .approvalCard:
      return approvalCardHosts(text).map { hosts in
        Host.allCases.map { PreferenceEdit.forAgent($0, .approvalCard(hosts.contains($0))) }
      }
    case .quitBehavior: return rawValue(text, as: QuitBehavior.self).map { [.quitBehavior($0)] }
    case .modeAfterPlan:
      return rawValue(text, as: PlanApprovalMode.self).map { [.modeAfterPlan($0)] }
    case .appearance: return rawValue(text, as: AppearanceChoice.self).map { [.appearance($0)] }
    case .keepAwakeDuration:
      return rawValue(text, as: KeepAwakeDuration.self).map { [.keepAwakeDuration($0)] }
    case .contextMode:
      return rawValue(text, as: ContextCheckpointMode.self).map { [.contextMode($0)] }
    case .panelSound: return panelSound(text).map { [.panelSound($0)] }
    case .accentColor: return accentColor(text).map { [.accentColor($0)] }
    case .keepAwakeBatteryCutoff: return batteryCutoff(text).map { [.keepAwakeBatteryCutoff($0)] }
    case .editorApp: return editorApp(text)
    case .contextStandardThresholds:
      return PreferenceRules.contextLadder(fromThousands: text).mapError(invalid).map {
        [.contextStandardThresholds($0)]
      }
    case .contextMillionThresholds:
      return PreferenceRules.contextLadder(fromThousands: text).mapError(invalid).map {
        [.contextMillionThresholds($0)]
      }
    case .contextModelThresholds:
      return modelThresholdList(text).map {
        modelThresholdEdits(listed: $0, current: current.contextCheckpoints.modelThresholds)
      }
    case .contextRearmBelow: return rearmPercent(text).map { [.contextRearmBelow($0)] }
    case .contextMaxCompactions: return maxCompactions(text).map { [.contextMaxCompactions($0)] }
    case .contextSoftChoices, .contextStatusChoices, .contextInsistChoices:
      return choices(text).map { [.contextChoices(name, $0)] }
    case .contextHandoffFile:
      return PreferenceRules.contextHandoffFile(text).mapError(invalid).map {
        [.contextHandoffFile($0)]
      }
    case .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteStop,
      .contextNoteCompact, .contextNoteHandoff, .contextNoteLimit:
      return PreferenceRules.contextNote(text).mapError(invalid).map { [.contextNote(name, $0)] }
    case .keepAwake, .waitingNotices, .contextCheckpointsEnabled:
      return .failure(.refused(name))
    }
  }
}
