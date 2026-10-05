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
  public static let systemPurpleLight = HexColor(red: 0xCB, green: 0x30, blue: 0xE0)
  public static let systemPurpleDark = HexColor(red: 0xDB, green: 0x34, blue: 0xF2)
  public static let systemOrangeLight = HexColor(red: 0xFF, green: 0x8D, blue: 0x28)
  public static let systemOrangeDark = HexColor(red: 0xFF, green: 0x92, blue: 0x30)
  public static let systemGreenLight = HexColor(red: 0x34, green: 0xC7, blue: 0x59)
  public static let systemGreenDark = HexColor(red: 0x30, green: 0xD1, blue: 0x58)
  public static let systemTealLight = HexColor(red: 0x00, green: 0xC3, blue: 0xD0)
  public static let systemTealDark = HexColor(red: 0x00, green: 0xD2, blue: 0xE0)
  public static let systemPinkLight = HexColor(red: 0xFF, green: 0x2D, blue: 0x55)
  public static let systemPinkDark = HexColor(red: 0xFF, green: 0x37, blue: 0x5F)

  public static func shellTokenColor(_ kind: ShellTokenKind, dark: Bool) -> HexColor? {
    let system: HexColor
    switch kind {
    case .command: system = dark ? systemPurpleDark : systemPurpleLight
    case .flag: system = dark ? systemOrangeDark : systemOrangeLight
    case .string: system = dark ? systemGreenDark : systemGreenLight
    case .variable: system = dark ? systemTealDark : systemTealLight
    case .operator: system = dark ? systemPinkDark : systemPinkLight
    case .comment: return nil
    }
    return dark
      ? AccentPalette.readable(system, on: darkCardBackground, towardLightness: 1)
      : AccentPalette.readable(system, on: lightCardBackground, towardLightness: 0)
  }
}
