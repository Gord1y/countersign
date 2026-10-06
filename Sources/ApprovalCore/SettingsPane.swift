import Foundation

public enum SettingsPane: String, CaseIterable, Sendable {
  case agents
  case panels
  case app
  case rules
  case skills
  case context
  case help
  case advanced

  public static let standard = SettingsPane.agents
  public static let sidebar: [SettingsPane] = sidebar(
    showsContext: false, showsSkills: Settings.defaultShowSkills)

  public static func sidebar(showsContext: Bool, showsSkills: Bool) -> [SettingsPane] {
    var panes: [SettingsPane] = [.agents, .app, .panels, .rules]
    if showsSkills { panes.append(.skills) }
    if showsContext { panes.append(.context) }
    panes.append(.help)
    return panes
  }

  public var title: String {
    switch self {
    case .agents: return "Agents"
    case .panels: return "Panels"
    case .app: return "App"
    case .rules: return "Rules"
    case .skills: return "Skills"
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
    case .rules:
      return "Allow or deny requests before a panel shows."
    case .skills:
      return
        "Skills and rules from countersign-skills. Countersign only reads them; it never installs"
        + " or changes anything."
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
    case .agents, .rules, .skills, .help, .advanced: return []
    case .panels:
      return [
        .idleSeconds, .graceSeconds, .armDelay, .chainedArmDelay, .snoozeMinutes, .quietHours,
        .handoffApps, .questionNotes, .modeAfterPlan,
        .panelSound, .waitingNoticeDelay, .waitingNoticeDuration,
        .approvalCard, .approvalCardDelay,
      ]
    case .app: return [.checkForUpdates, .quitBehavior, .appearance, .accentColor, .showSkills]
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
