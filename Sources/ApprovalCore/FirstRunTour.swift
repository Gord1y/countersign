import Foundation

public enum FirstRunTourSegment: Sendable, Equatable {
  case text(String)
  case key(String)
}

public enum FirstRunTourStep: Int, CaseIterable, Sendable, Equatable {
  case wireAgents = 1
  case howAPanelWaits = 2
  case tryIt = 3
  case makeItYours = 4

  public var title: String {
    switch self {
    case .wireAgents: return "Wire your agents"
    case .howAPanelWaits: return "How a panel waits"
    case .tryIt: return "Try it"
    case .makeItYours: return "Make it yours"
    }
  }

  public var bodySegments: [FirstRunTourSegment] {
    switch self {
    case .wireAgents:
      return [
        .text(
          "The Agents tab connects Claude Code, Codex, Cursor and Antigravity. Wiring one adds a"
            + " hook to its own config file, after showing you the change. Some agents need one"
            + " more step afterwards; Codex, for example, asks you to trust the hook in a"
            + " terminal.")
      ]
    case .howAPanelWaits:
      return [
        .text(
          "A panel appears once you've paused for a moment, and Claude Code gets a short grace"
            + " period first in case you answer in the chat. When it appears, it ignores keys and"
            + " clicks for a moment so nothing you were already typing lands on it. Then "),
        .key("⏎"),
        .text(" approves, "),
        .key("esc"),
        .text(" answers in the chat, "),
        .key("⌫"),
        .text(" opens Deny and "),
        .key("⌘⏎"),
        .text(" opens more choices."),
      ]
    case .tryIt:
      return [
        .text(
          "Panels has Show a test panel buttons for a command, a question and a plan. A test"
            + " panel appears right away with your current settings, and nothing you do in it"
            + " reaches an agent.")
      ]
    case .makeItYours:
      return [
        .text(
          "App holds Launch at login, what quitting the menu-bar app does, and an Advanced…"
            + " button for the config file. Every setting explains itself with ⓘ and gets a reset"
            + " button once you change it.")
      ]
    }
  }
}

public enum FirstRunTour {
  public static let stepCount = FirstRunTourStep.allCases.count
}
