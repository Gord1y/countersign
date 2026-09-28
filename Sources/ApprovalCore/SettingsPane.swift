import Foundation

public enum SettingsPane: String, CaseIterable, Sendable {
  case agents
  case panels
  case app
  case help
  case advanced

  public static let standard = SettingsPane.agents
  public static let sidebar: [SettingsPane] = [.agents, .app, .panels, .help]

  public init(storedValue: String?) {
    self = storedValue.flatMap(SettingsPane.init(rawValue:)) ?? .standard
  }

  public var title: String {
    switch self {
    case .agents: return "Agents"
    case .panels: return "Panels"
    case .app: return "App"
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
        "How approval panels behave, for every agent. Saved to config.json as soon as you"
        + " change them."
    case .app:
      return "What the menu-bar app does, and how panels and Settings look."
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
        .idleSeconds, .graceSeconds, .armDelay, .chainedArmDelay, .snoozeMinutes, .handoffApps,
        .questionNotes, .modeAfterPlan,
      ]
    case .app: return [.checkForUpdates, .quitBehavior, .appearance, .accentColor]
    }
  }
}
