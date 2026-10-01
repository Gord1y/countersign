import Foundation

public enum PreferenceOverrides {
  public static let fileOnlyTopLevelKeys: [String] = ConfigFileParser.topLevelKeys
    .subtracting(PreferenceName.allCases.compactMap(\.keyPath.first))
    .subtracting(["hosts", "$schema"])
    .sorted()

  public static var fileOnlyNote: String {
    fileOnlyNote(keys: fileOnlyTopLevelKeys)
  }

  static func fileOnlyNote(keys: [String]) -> String {
    let perAgent = "Only the file can set values for one agent, under hosts"
    guard !keys.isEmpty else { return "\(perAgent)." }
    return "\(perAgent), and \(keys.joined(separator: ", "))."
  }

  public static func values(in overrides: ConfigFile.HostOverrides?) -> [String] {
    guard let overrides else { return [] }
    var values: [String] = []
    if let idleSeconds = overrides.idleSeconds {
      values.append(named(.idleSeconds, PreferenceRules.secondsText(idleSeconds)))
    }
    if let graceSeconds = overrides.graceSeconds {
      values.append(named(.graceSeconds, PreferenceRules.secondsText(graceSeconds)))
    }
    if let armDelay = overrides.armDelay {
      values.append(named(.armDelay, PreferenceRules.secondsText(armDelay)))
    }
    if let chainedArmDelay = overrides.chainedArmDelay {
      values.append(named(.chainedArmDelay, PreferenceRules.secondsText(chainedArmDelay)))
    }
    if let handoffApps = overrides.handoffApps {
      values.append(
        named(.handoffApps, handoffApps.isEmpty ? "none" : handoffApps.joined(separator: ", ")))
    }
    if let snoozePresets = overrides.snoozePresets {
      let wholeMinutes = snoozePresets.allSatisfy { $0.truncatingRemainder(dividingBy: 60) == 0 }
      let suffix = wholeMinutes ? " min" : ""
      values.append(named(.snoozeMinutes, "\(PreferenceRules.snoozeText(snoozePresets))\(suffix)"))
    }
    if let includeHeadlessSessions = overrides.includeHeadlessSessions {
      values.append("headless sessions \(includeHeadlessSessions ? "on" : "off")")
    }
    return values
  }

  public static func note(for host: Host, in file: ConfigFile) -> String? {
    let values = values(in: file.overrides(for: host))
    guard !values.isEmpty else { return nil }
    return "Own values in config.json: \(values.joined(separator: "; "))"
  }

  private static func named(_ name: PreferenceName, _ value: String) -> String {
    "\(name.title.lowercased()) \(value)"
  }
}
