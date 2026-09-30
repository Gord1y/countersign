import Foundation

public enum PanelAnnouncement {
  public static let ready = "Ready"
  public static let notAvailableYet = "Not available yet"

  public static func text(for request: ApprovalRequest) -> String {
    var who = [request.host.displayName, request.projectName]
    if let agentType = request.agentType {
      who.append("subagent \(agentType)")
    }
    return "\(who.joined(separator: ", ")): \(action(for: request))"
  }

  public static func shortcutHint(for key: String) -> String {
    "Shortcut: \(spokenKey(key))"
  }

  static func spokenKey(_ key: String) -> String {
    switch key {
    case "⏎": return "Return"
    case "⌘⏎": return "Command-Return"
    case "⌫": return "Delete"
    case "esc": return "Escape"
    default: return key
    }
  }

  private static func action(for request: ApprovalRequest) -> String {
    switch request.kind {
    case .permission: return "asks permission to use \(request.toolName)"
    case .questions(let questions):
      return questions.count == 1 ? "asks a question" : "asks \(questions.count) questions"
    case .plan: return "proposes a plan"
    case .contextCheckpoint: return "suggests a context checkpoint"
    }
  }
}

public enum DiffLineSpeech {
  public static func label(for line: NumberedLine, showsNumbers: Bool) -> String {
    var parts: [String] = []
    switch line.kind {
    case .added: parts.append("Added")
    case .removed: parts.append("Removed")
    case .context: break
    }
    let number = line.kind == .removed ? line.oldNumber : (line.newNumber ?? line.oldNumber)
    if showsNumbers, let number {
      parts.append("line \(number)")
    }
    let prefix = parts.joined(separator: ", ")
    let text = line.text.isEmpty ? "blank" : line.text
    return prefix.isEmpty ? text : "\(prefix): \(text)"
  }
}

public enum PanelContrast {
  public static let lightCardBackground = HexColor(red: 0xF2, green: 0xF2, blue: 0xF2)
  public static let darkCardBackground = HexColor(red: 0x29, green: 0x29, blue: 0x29)
  public static let systemOrangeLight = HexColor(red: 0xFF, green: 0x95, blue: 0x00)
  public static let systemOrangeDark = HexColor(red: 0xFF, green: 0x9F, blue: 0x0A)

  public static var increasedContrastOrangeLight: HexColor {
    AccentPalette.readable(systemOrangeLight, on: lightCardBackground, towardLightness: 0)
  }

  public static var increasedContrastOrangeDark: HexColor {
    AccentPalette.readable(systemOrangeDark, on: darkCardBackground, towardLightness: 1)
  }
}
