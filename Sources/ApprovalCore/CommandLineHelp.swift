import Foundation

public enum CommandLineHelp {
  public static func text(version: String) -> String {
    var lines = [
      "Countersign \(version): a native macOS approval panel for Claude Code, Codex, Cursor and Antigravity.",
      "",
      "Usage: countersign <command>",
      "",
      "Commands:",
      entry("setup", "Open the setup window; setup --cli does the same in the terminal"),
      entry("settings", "Open the same window"),
      entry("doctor", "Check your setup and print a plain, pasteable report"),
      entry("status", "Active or paused, queued requests, quiet time, log location"),
      entry("pause", "Turn panels off; every prompt goes to its chat"),
      entry("resume", "Turn panels back on"),
      entry(
        "snooze <time>|off", "Quiet time for every prompt: 90s, 15m, 1h or minutes; off ends it"),
      entry(
        "test-panel [kind]",
        "Show a test panel (command, question, plan or context); nothing is sent"
      ),
      entry("help", "Show this help"),
      entry("--version", "Print the installed version"),
      "",
      "hook runs from your agents' hooks; preview and snapshot are for development.",
    ]

    var helpLines: [String] = []
    if let documentationURL = CompanionMenu.documentationURL {
      helpLines.append(entry("Documentation", documentationURL.absoluteString))
    }
    if let askAQuestionURL = CompanionMenu.askAQuestionURL {
      helpLines.append(entry("Ask a question", askAQuestionURL.absoluteString))
    }
    if let formURL = BugReportURL.formURL {
      helpLines.append(entry("Report a problem", formURL.absoluteString))
      helpLines.append(entry("", "(paste the output of countersign doctor)"))
    }
    if let contactDeveloperURL = CompanionMenu.contactDeveloperURL {
      helpLines.append(entry("Contact the developer", contactDeveloperURL.absoluteString))
    }
    if !helpLines.isEmpty {
      lines.append("")
      lines.append("Help:")
      lines.append(contentsOf: helpLines)
    }

    var supportLines: [String] = []
    if let sponsorURL = CompanionMenu.sponsorURL {
      supportLines.append(entry("Sponsor on GitHub", sponsorURL.absoluteString))
    }
    if let buyMeACoffeeURL = CompanionMenu.buyMeACoffeeURL {
      supportLines.append(entry("Buy Me a Coffee", buyMeACoffeeURL.absoluteString))
    }
    if !supportLines.isEmpty {
      lines.append("")
      lines.append("Support Countersign:")
      lines.append(contentsOf: supportLines)
    }

    return lines.joined(separator: "\n")
  }

  private static func entry(_ label: String, _ description: String) -> String {
    "  " + label.padding(toLength: 23, withPad: " ", startingAt: 0) + description
  }
}
