import Foundation

public enum SettingsPane: String, CaseIterable, Sendable {
  case agents
  case panels
  case app
  case context
  case help
  case advanced

  public static let standard = SettingsPane.agents
  public static let sidebar: [SettingsPane] = sidebar(showsContext: false)

  public static func sidebar(showsContext: Bool) -> [SettingsPane] {
    showsContext ? [.agents, .app, .panels, .context, .help] : [.agents, .app, .panels, .help]
  }

  public init(storedValue: String?) {
    self.init(storedValue: storedValue, showsContext: true)
  }

  public init(storedValue: String?, showsContext: Bool) {
    let stored = storedValue.flatMap(SettingsPane.init(rawValue:))
    self = stored.flatMap { $0 == .context && !showsContext ? nil : $0 } ?? .standard
  }

  public var title: String {
    switch self {
    case .agents: return "Agents"
    case .panels: return "Panels"
    case .app: return "App"
    case .context: return "Context"
    case .help: return "Help"
    case .advanced: return "Advanced"
    }
  }

  public var subtitle: String {
    switch self {
    case .agents:
      return
        "Which coding agents Countersign answers for. Changes each agent's own hook file,"
        + " after showing you the change."
    case .panels:
      return
        "How approval panels behave. Saved to config.json as soon as you"
        + " change them."
    case .app:
      return "What the menu-bar app does, and how panels and Settings look."
    case .context:
      return
        "Context checkpoints for Claude Code sessions. Saved to config.json as soon as you"
        + " change them."
    case .help:
      return "Guides and answers, updates, and ways to support Countersign."
    case .advanced:
      return "Where your settings are stored, and what only the file can set."
    }
  }

  public var preferenceNames: [PreferenceName] {
    switch self {
    case .agents, .help, .advanced: return []
    case .panels:
      return [
        .idleSeconds, .graceSeconds, .armDelay, .chainedArmDelay, .snoozeMinutes, .quietHours,
        .handoffApps, .questionNotes, .modeAfterPlan,
        .panelSound, .waitingNoticeMinutes, .approvalCard, .approvalCardDelay,
      ]
    case .app: return [.checkForUpdates, .quitBehavior, .appearance, .accentColor]
    case .context:
      return [
        .contextMode, .contextStandardThresholds, .contextMillionThresholds,
        .contextModelThresholds, .contextRearmBelow, .contextHandoffFile, .contextNoteSoft,
        .contextNoteStatus, .contextNoteInsist, .contextNoteCompact, .contextNoteHandoff,
        .contextMenuBarMeter,
      ]
    }
  }
}
