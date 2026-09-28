import Foundation

public struct ConfigFile: Sendable, Equatable {
  public struct HostOverrides: Sendable, Equatable {
    public var armDelay: Double?
    public var chainedArmDelay: Double?
    public var idleSeconds: Double?
    public var graceSeconds: Double?
    public var handoffApps: [String]?
    public var snoozeMinutes: [Int]?
    public var includeHeadlessSessions: Bool?

    public init(
      armDelay: Double? = nil,
      chainedArmDelay: Double? = nil,
      idleSeconds: Double? = nil,
      graceSeconds: Double? = nil,
      handoffApps: [String]? = nil,
      snoozeMinutes: [Int]? = nil,
      includeHeadlessSessions: Bool? = nil
    ) {
      self.armDelay = armDelay
      self.chainedArmDelay = chainedArmDelay
      self.idleSeconds = idleSeconds
      self.graceSeconds = graceSeconds
      self.handoffApps = handoffApps
      self.snoozeMinutes = snoozeMinutes
      self.includeHeadlessSessions = includeHeadlessSessions
    }
  }

  public var armDelay: Double?
  public var chainedArmDelay: Double?
  public var idleSeconds: Double?
  public var graceSeconds: Double?
  public var handoffApps: [String]?
  public var snoozeMinutes: [Int]?
  public var checkForUpdates: Bool?
  public var quitBehavior: QuitBehavior?
  public var modeAfterPlan: PlanApprovalMode?
  public var includeHeadlessSessions: Bool?
  public var questionNotes: Bool?
  public var appearance: AppearanceChoice?
  public var accentColor: HexColor?
  public var editorApp: String?
  public var claude: HostOverrides?
  public var codex: HostOverrides?
  public var cursor: HostOverrides?
  public var antigravity: HostOverrides?

  public init(
    armDelay: Double? = nil,
    chainedArmDelay: Double? = nil,
    idleSeconds: Double? = nil,
    graceSeconds: Double? = nil,
    handoffApps: [String]? = nil,
    snoozeMinutes: [Int]? = nil,
    checkForUpdates: Bool? = nil,
    quitBehavior: QuitBehavior? = nil,
    modeAfterPlan: PlanApprovalMode? = nil,
    includeHeadlessSessions: Bool? = nil,
    questionNotes: Bool? = nil,
    appearance: AppearanceChoice? = nil,
    accentColor: HexColor? = nil,
    editorApp: String? = nil,
    claude: HostOverrides? = nil,
    codex: HostOverrides? = nil,
    cursor: HostOverrides? = nil,
    antigravity: HostOverrides? = nil
  ) {
    self.armDelay = armDelay
    self.chainedArmDelay = chainedArmDelay
    self.idleSeconds = idleSeconds
    self.graceSeconds = graceSeconds
    self.handoffApps = handoffApps
    self.snoozeMinutes = snoozeMinutes
    self.checkForUpdates = checkForUpdates
    self.quitBehavior = quitBehavior
    self.modeAfterPlan = modeAfterPlan
    self.includeHeadlessSessions = includeHeadlessSessions
    self.questionNotes = questionNotes
    self.appearance = appearance
    self.accentColor = accentColor
    self.editorApp = editorApp
    self.claude = claude
    self.codex = codex
    self.cursor = cursor
    self.antigravity = antigravity
  }

  public func overrides(for host: Host) -> HostOverrides? {
    switch host {
    case .claude: return claude
    case .codex: return codex
    case .cursor: return cursor
    case .antigravity: return antigravity
    }
  }
}

public enum ConfigFileLoader {
  public static func load(paths: AppPaths) -> (file: ConfigFile, logLines: [String]) {
    guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
      return (ConfigFile(), [])
    }
    guard let data = try? Data(contentsOf: paths.configFile) else {
      return (ConfigFile(), ["config.json could not be read, using defaults"])
    }
    return ConfigFileParser.parse(data)
  }
}

public enum ConfigFileParser {
  static let topLevelKeys: Set<String> = [
    "armDelay", "chainedArmDelay", "idleSeconds", "graceSeconds", "handoffApps",
    "snoozeMinutes", "checkForUpdates", "quitBehavior", "modeAfterPlan",
    "includeHeadlessSessions", "questionNotes", "editorApp", "hosts",
    "appearance", "accentColor",
    "$schema",
  ]
  static let hostKeys: Set<String> = [
    "armDelay", "chainedArmDelay", "idleSeconds", "graceSeconds", "handoffApps",
    "snoozeMinutes", "includeHeadlessSessions",
  ]

  public static func parse(_ data: Data) -> (file: ConfigFile, logLines: [String]) {
    let decoded: JSONValue
    do {
      decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      return (ConfigFile(), ["config.json is not valid JSON, using defaults"])
    }
    guard case .object(let root) = decoded else {
      return (ConfigFile(), ["config.json does not contain a JSON object, using defaults"])
    }

    var logLines: [String] = []
    var file = ConfigFile()

    for key in root.keys where !topLevelKeys.contains(key) {
      logLines.append("unknown key \"\(key)\", ignored")
    }

    file.armDelay = readArmDelay(
      root["armDelay"], path: "armDelay", defaultValue: Settings.defaultArmDelay,
      logLines: &logLines)
    file.chainedArmDelay = readArmDelay(
      root["chainedArmDelay"], path: "chainedArmDelay",
      defaultValue: Settings.defaultChainedArmDelay, logLines: &logLines)
    file.idleSeconds = readNonNegativeNumber(
      root["idleSeconds"], path: "idleSeconds", defaultValue: Settings.defaultIdleSeconds,
      logLines: &logLines)
    file.graceSeconds = readNonNegativeNumber(
      root["graceSeconds"], path: "graceSeconds", defaultValue: Settings.defaultGraceSeconds,
      logLines: &logLines)
    file.handoffApps = readHandoffApps(
      root["handoffApps"], path: "handoffApps", logLines: &logLines)
    file.snoozeMinutes = readSnoozeMinutes(
      root["snoozeMinutes"], path: "snoozeMinutes", logLines: &logLines)
    file.checkForUpdates = readBool(
      root["checkForUpdates"], path: "checkForUpdates",
      defaultValue: Settings.defaultCheckForUpdates, logLines: &logLines)
    file.quitBehavior = readQuitBehavior(
      root["quitBehavior"], path: "quitBehavior", logLines: &logLines)
    file.modeAfterPlan = readModeAfterPlan(
      root["modeAfterPlan"], path: "modeAfterPlan", logLines: &logLines)
    file.includeHeadlessSessions = readBool(
      root["includeHeadlessSessions"], path: "includeHeadlessSessions",
      defaultValue: Settings.defaultIncludeHeadlessSessions, logLines: &logLines)
    file.questionNotes = readBool(
      root["questionNotes"], path: "questionNotes",
      defaultValue: Settings.defaultQuestionNotes, logLines: &logLines)
    file.appearance = readAppearance(
      root["appearance"], path: "appearance", logLines: &logLines)
    file.accentColor = readAccentColor(
      root["accentColor"], path: "accentColor", logLines: &logLines)
    file.editorApp = readEditorApp(root["editorApp"], path: "editorApp", logLines: &logLines)

    if let hostsValue = root["hosts"] {
      switch hostsValue {
      case .object(let hostsObject):
        for key in hostsObject.keys where Host(rawValue: key) == nil {
          logLines.append("unknown key \"hosts.\(key)\", ignored")
        }
        file.claude = readHostOverrides(
          hostsObject["claude"], path: "hosts.claude", logLines: &logLines)
        file.codex = readHostOverrides(
          hostsObject["codex"], path: "hosts.codex", logLines: &logLines)
        file.cursor = readHostOverrides(
          hostsObject["cursor"], path: "hosts.cursor", logLines: &logLines)
        file.antigravity = readHostOverrides(
          hostsObject["antigravity"], path: "hosts.antigravity", logLines: &logLines)
      default:
        logLines.append("hosts: expected an object, ignored")
      }
    }

    return (file, logLines)
  }

  private static func readHostOverrides(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> ConfigFile.HostOverrides? {
    guard let value else { return nil }
    guard case .object(let object) = value else {
      logLines.append("\(path): expected an object, ignored")
      return nil
    }
    for key in object.keys where !hostKeys.contains(key) {
      logLines.append("unknown key \"\(path).\(key)\", ignored")
    }
    return ConfigFile.HostOverrides(
      armDelay: readArmDelay(
        object["armDelay"], path: "\(path).armDelay", defaultValue: Settings.defaultArmDelay,
        logLines: &logLines),
      chainedArmDelay: readArmDelay(
        object["chainedArmDelay"], path: "\(path).chainedArmDelay",
        defaultValue: Settings.defaultChainedArmDelay, logLines: &logLines),
      idleSeconds: readNonNegativeNumber(
        object["idleSeconds"], path: "\(path).idleSeconds",
        defaultValue: Settings.defaultIdleSeconds, logLines: &logLines),
      graceSeconds: readNonNegativeNumber(
        object["graceSeconds"], path: "\(path).graceSeconds",
        defaultValue: Settings.defaultGraceSeconds, logLines: &logLines),
      handoffApps: readHandoffApps(
        object["handoffApps"], path: "\(path).handoffApps", logLines: &logLines),
      snoozeMinutes: readSnoozeMinutes(
        object["snoozeMinutes"], path: "\(path).snoozeMinutes", logLines: &logLines),
      includeHeadlessSessions: readBool(
        object["includeHeadlessSessions"], path: "\(path).includeHeadlessSessions",
        defaultValue: Settings.defaultIncludeHeadlessSessions, logLines: &logLines))
  }

  private static func numberValue(_ value: JSONValue) -> Double? {
    switch value {
    case .int(let intValue): return Double(intValue)
    case .double(let doubleValue): return doubleValue
    default: return nil
    }
  }

  private static func integerValue(_ value: JSONValue) -> Int? {
    switch value {
    case .int(let intValue): return Int(intValue)
    case .double(let doubleValue): return Int(exactly: doubleValue)
    default: return nil
    }
  }

  private static func formatNumber(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
  }

  private static func readArmDelay(
    _ value: JSONValue?, path: String, defaultValue: Double, logLines: inout [String]
  ) -> Double? {
    guard let value else { return nil }
    guard let number = numberValue(value) else {
      logLines.append("\(path): not a number, using default \(formatNumber(defaultValue))")
      return nil
    }
    if !Settings.armDelayRange.contains(number) {
      let clamped = min(
        max(number, Settings.armDelayRange.lowerBound), Settings.armDelayRange.upperBound)
      logLines.append(
        "\(path): \(formatNumber(number)) is out of range 0...3, clamped to \(formatNumber(clamped))"
      )
      return clamped
    }
    return number
  }

  private static func readNonNegativeNumber(
    _ value: JSONValue?, path: String, defaultValue: Double, logLines: inout [String]
  ) -> Double? {
    guard let value else { return nil }
    guard let number = numberValue(value), number >= 0 else {
      logLines.append(
        "\(path): not a non-negative number, using default \(formatNumber(defaultValue))")
      return nil
    }
    return number
  }

  private static func readBool(
    _ value: JSONValue?, path: String, defaultValue: Bool, logLines: inout [String]
  ) -> Bool? {
    guard let value else { return nil }
    guard let bool = value.boolValue else {
      logLines.append("\(path): not a boolean, using default \(defaultValue)")
      return nil
    }
    return bool
  }

  private static func readQuitBehavior(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> QuitBehavior? {
    guard let value else { return nil }
    guard let behavior = value.stringValue.flatMap(QuitBehavior.init(rawValue:)) else {
      logLines.append(
        "\(path): expected \"ask\", \"keepShowing\" or \"pause\", using default"
          + " \"\(Settings.defaultQuitBehavior.rawValue)\"")
      return nil
    }
    return behavior
  }

  private static func readModeAfterPlan(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> PlanApprovalMode? {
    guard let value else { return nil }
    guard let mode = value.stringValue.flatMap(PlanApprovalMode.init(rawValue:)) else {
      logLines.append(
        "\(path): expected \"default\", \"acceptEdits\" or \"auto\", using default"
          + " \"\(Settings.defaultModeAfterPlan.rawValue)\"")
      return nil
    }
    return mode
  }

  private static func readAppearance(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> AppearanceChoice? {
    guard let value else { return nil }
    guard let appearance = value.stringValue.flatMap(AppearanceChoice.init(rawValue:)) else {
      logLines.append(
        "\(path): expected \"system\", \"light\" or \"dark\", using default"
          + " \"\(Settings.defaultAppearance.rawValue)\"")
      return nil
    }
    return appearance
  }

  private static func readAccentColor(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> HexColor? {
    guard let value else { return nil }
    guard let color = value.stringValue.flatMap(HexColor.init(hex:)) else {
      logLines.append(
        "\(path): expected \"#RRGGBB\", using default"
          + " \"\(Settings.defaultAccentColor.hex)\"")
      return nil
    }
    return color
  }

  private static func readEditorApp(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> String? {
    guard let value else { return nil }
    guard let string = value.stringValue, !string.isEmpty else {
      logLines.append("\(path): expected a non-empty string, using the default app")
      return nil
    }
    return string
  }

  private static func readHandoffApps(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> [String]? {
    guard let value else { return nil }
    guard case .array(let array) = value else {
      logLines.append("\(path): not an array, using default []")
      return nil
    }
    var apps: [String] = []
    for element in array {
      guard let string = element.stringValue else {
        logLines.append("\(path): contains a non-string value, using default []")
        return nil
      }
      apps.append(string)
    }
    return apps
  }

  private static func readSnoozeMinutes(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> [Int]? {
    guard let value else { return nil }
    let fallback = "\(Settings.defaultSnoozeMinutes)"
    guard case .array(let array) = value, (1...6).contains(array.count) else {
      logLines.append("\(path): expected 1 to 6 integers, using default \(fallback)")
      return nil
    }
    var minutes: [Int] = []
    for element in array {
      guard let intValue = integerValue(element), (1...1440).contains(intValue) else {
        logLines.append("\(path): expected integers from 1 to 1440, using default \(fallback)")
        return nil
      }
      minutes.append(intValue)
    }
    return minutes
  }
}
