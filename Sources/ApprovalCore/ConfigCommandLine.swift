import Foundation

extension PreferenceName {
  public var commandLineKey: String {
    keyPath.joined(separator: ".")
  }

  public init?(commandLineKey: String) {
    guard let name = Self.allCases.first(where: { $0.commandLineKey == commandLineKey }) else {
      return nil
    }
    self = name
  }
}

public enum ConfigCommandLine: Sendable, Equatable {
  case list
  case get(PreferenceName)
  case set(PreferenceName, String)
  case reset(PreferenceName)
  case resetPane(SettingsPane)
  case open
  case unknownKey(String)
  case unknownPane(String)

  public static let usage = """
    usage: countersign config get [key]
           countersign config set <key> <value>
           countersign config reset <key>|--pane <panels|app|context>
           countersign config open
    """
  public static let alreadyDefaults = "already at their defaults"

  public static func parse(_ arguments: [String]) -> ConfigCommandLine? {
    guard let subcommand = arguments.first else { return nil }
    let rest = Array(arguments.dropFirst())
    switch subcommand {
    case "get":
      switch rest.count {
      case 0: return .list
      case 1: return keyed(rest[0]) { .get($0) }
      default: return nil
      }
    case "set":
      guard rest.count == 2 else { return nil }
      return keyed(rest[0]) { .set($0, rest[1]) }
    case "reset":
      return parseReset(rest)
    case "open":
      return rest.isEmpty ? .open : nil
    default:
      return nil
    }
  }

  public static func unknownKeyError(_ key: String) -> String {
    "error: no setting named \"\(key)\"; countersign config get lists them"
  }

  public static func unknownPaneError(_ pane: String) -> String {
    "error: no Settings pane named \"\(pane)\"; use panels, app or context"
  }

  public static func noSettingsError(_ pane: SettingsPane) -> String {
    "error: \(pane.rawValue) has no settings to reset; use panels, app or context"
  }

  public static func row(_ name: PreferenceName, values: PreferenceValues) -> String {
    let text =
      name.noteName == nil
      ? ConfigValue.text(name, values: values)
      : PreferenceReset.valueText(name, in: values)
    return "\(name.commandLineKey) = \(text)"
  }

  private static func keyed(
    _ key: String, _ make: (PreferenceName) -> ConfigCommandLine
  ) -> ConfigCommandLine {
    guard let name = PreferenceName(commandLineKey: key) else { return .unknownKey(key) }
    return make(name)
  }

  private static func parseReset(_ arguments: [String]) -> ConfigCommandLine? {
    if arguments.first == "--pane" {
      guard arguments.count == 2 else { return nil }
      guard let pane = SettingsPane(rawValue: arguments[1]) else {
        return .unknownPane(arguments[1])
      }
      return .resetPane(pane)
    }
    guard arguments.count == 1 else { return nil }
    return keyed(arguments[0]) { .reset($0) }
  }
}
