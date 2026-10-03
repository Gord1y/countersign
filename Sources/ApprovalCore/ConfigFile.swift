import Foundation

public struct ConfigFile: Sendable, Equatable {
  public struct HostOverrides: Sendable, Equatable {
    public var armDelay: Double?
    public var chainedArmDelay: Double?
    public var idleSeconds: Double?
    public var graceSeconds: Double?
    public var handoffApps: [String]?
    public var snoozePresets: [TimeInterval]?
    public var includeHeadlessSessions: Bool?
    public var waitingNoticeDelay: TimeInterval?
    public var approvalCard: Bool?
    public var approvalCardDelay: Double?

    public init(
      armDelay: Double? = nil,
      chainedArmDelay: Double? = nil,
      idleSeconds: Double? = nil,
      graceSeconds: Double? = nil,
      handoffApps: [String]? = nil,
      snoozePresets: [TimeInterval]? = nil,
      includeHeadlessSessions: Bool? = nil,
      waitingNoticeDelay: TimeInterval? = nil,
      approvalCard: Bool? = nil,
      approvalCardDelay: Double? = nil
    ) {
      self.armDelay = armDelay
      self.chainedArmDelay = chainedArmDelay
      self.idleSeconds = idleSeconds
      self.graceSeconds = graceSeconds
      self.handoffApps = handoffApps
      self.snoozePresets = snoozePresets
      self.includeHeadlessSessions = includeHeadlessSessions
      self.waitingNoticeDelay = waitingNoticeDelay
      self.approvalCard = approvalCard
      self.approvalCardDelay = approvalCardDelay
    }
  }

  public var armDelay: Double?
  public var chainedArmDelay: Double?
  public var idleSeconds: Double?
  public var graceSeconds: Double?
  public var handoffApps: [String]?
  public var snoozePresets: [TimeInterval]?
  public var quietHours: [QuietWindow]?
  public var checkForUpdates: Bool?
  public var quitBehavior: QuitBehavior?
  public var modeAfterPlan: PlanApprovalMode?
  public var panelSound: String?
  public var waitingNotices: Bool?
  public var waitingNoticeDelay: TimeInterval?
  public var waitingNoticeDuration: TimeInterval?
  public var approvalCard: Bool?
  public var approvalCardDelay: Double?
  public var includeHeadlessSessions: Bool?
  public var questionNotes: Bool?
  public var appearance: AppearanceChoice?
  public var accentColor: HexColor?
  public var editorApp: String?
  public var claude: HostOverrides?
  public var codex: HostOverrides?
  public var cursor: HostOverrides?
  public var antigravity: HostOverrides?
  public var contextCheckpoints: ContextCheckpointFileValues?
  public var contextCheckpointsClaude: ContextCheckpointFileValues?
  public var rules: [ApprovalRule]?

  public init(
    armDelay: Double? = nil,
    chainedArmDelay: Double? = nil,
    idleSeconds: Double? = nil,
    graceSeconds: Double? = nil,
    handoffApps: [String]? = nil,
    snoozePresets: [TimeInterval]? = nil,
    quietHours: [QuietWindow]? = nil,
    checkForUpdates: Bool? = nil,
    quitBehavior: QuitBehavior? = nil,
    modeAfterPlan: PlanApprovalMode? = nil,
    panelSound: String? = nil,
    waitingNotices: Bool? = nil,
    waitingNoticeDelay: TimeInterval? = nil,
    waitingNoticeDuration: TimeInterval? = nil,
    approvalCard: Bool? = nil,
    approvalCardDelay: Double? = nil,
    includeHeadlessSessions: Bool? = nil,
    questionNotes: Bool? = nil,
    appearance: AppearanceChoice? = nil,
    accentColor: HexColor? = nil,
    editorApp: String? = nil,
    claude: HostOverrides? = nil,
    codex: HostOverrides? = nil,
    cursor: HostOverrides? = nil,
    antigravity: HostOverrides? = nil,
    contextCheckpoints: ContextCheckpointFileValues? = nil,
    contextCheckpointsClaude: ContextCheckpointFileValues? = nil,
    rules: [ApprovalRule]? = nil
  ) {
    self.armDelay = armDelay
    self.chainedArmDelay = chainedArmDelay
    self.idleSeconds = idleSeconds
    self.graceSeconds = graceSeconds
    self.handoffApps = handoffApps
    self.snoozePresets = snoozePresets
    self.quietHours = quietHours
    self.checkForUpdates = checkForUpdates
    self.quitBehavior = quitBehavior
    self.modeAfterPlan = modeAfterPlan
    self.panelSound = panelSound
    self.waitingNotices = waitingNotices
    self.waitingNoticeDelay = waitingNoticeDelay
    self.waitingNoticeDuration = waitingNoticeDuration
    self.approvalCard = approvalCard
    self.approvalCardDelay = approvalCardDelay
    self.includeHeadlessSessions = includeHeadlessSessions
    self.questionNotes = questionNotes
    self.appearance = appearance
    self.accentColor = accentColor
    self.editorApp = editorApp
    self.claude = claude
    self.codex = codex
    self.cursor = cursor
    self.antigravity = antigravity
    self.contextCheckpoints = contextCheckpoints
    self.contextCheckpointsClaude = contextCheckpointsClaude
    self.rules = rules
  }

  public var quietSchedule: QuietSchedule {
    QuietSchedule(windows: quietHours ?? [])
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
  public static func load(
    paths: AppPaths, soundNames: [String] = PanelSound.systemNames
  ) -> (file: ConfigFile, logLines: [String]) {
    guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
      return (ConfigFile(), [])
    }
    guard let data = try? Data(contentsOf: paths.configFile) else {
      return (ConfigFile(), ["config.json could not be read, using defaults"])
    }
    return ConfigFileParser.parse(data, soundNames: soundNames)
  }
}

public enum ConfigFileParser {
  static let topLevelKeys: Set<String> = [
    "armDelay", "chainedArmDelay", "idleSeconds", "graceSeconds", "handoffApps",
    "snoozeMinutes", "quietHours", "checkForUpdates", "quitBehavior", "modeAfterPlan",
    "panelSound", "waitingNotices", "waitingNoticeDelay", "waitingNoticeDuration", "approvalCard",
    "approvalCardDelay", "includeHeadlessSessions", "questionNotes", "editorApp", "hosts",
    "appearance", "accentColor", "contextCheckpoints", "rules",
    "$schema",
  ]
  static let contextCheckpointKeys: Set<String> = [
    "enabled", "mode", "thresholds", "modelThresholds", "rearmBelow", "handoffFile", "notes",
    "menuBarMeter", "hosts",
  ]
  static let hostKeys: Set<String> = [
    "armDelay", "chainedArmDelay", "idleSeconds", "graceSeconds", "handoffApps",
    "snoozeMinutes", "includeHeadlessSessions", "waitingNoticeDelay", "approvalCard",
    "approvalCardDelay",
  ]

  public static func parse(_ data: Data, soundNames: [String] = PanelSound.systemNames) -> (
    file: ConfigFile, logLines: [String]
  ) {
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
      root["idleSeconds"], path: "idleSeconds", range: Settings.idleSecondsRange,
      defaultValue: Settings.defaultIdleSeconds, logLines: &logLines)
    file.graceSeconds = readNonNegativeNumber(
      root["graceSeconds"], path: "graceSeconds", range: Settings.graceSecondsRange,
      defaultValue: Settings.defaultGraceSeconds, logLines: &logLines)
    file.handoffApps = readHandoffApps(
      root["handoffApps"], path: "handoffApps", logLines: &logLines)
    file.snoozePresets = readSnoozePresets(
      root["snoozeMinutes"], path: "snoozeMinutes", logLines: &logLines)
    file.quietHours = readQuietHours(
      root["quietHours"], path: "quietHours", logLines: &logLines)
    file.checkForUpdates = readBool(
      root["checkForUpdates"], path: "checkForUpdates",
      defaultValue: Settings.defaultCheckForUpdates, logLines: &logLines)
    file.quitBehavior = readQuitBehavior(
      root["quitBehavior"], path: "quitBehavior", logLines: &logLines)
    file.modeAfterPlan = readModeAfterPlan(
      root["modeAfterPlan"], path: "modeAfterPlan", logLines: &logLines)
    file.panelSound = readPanelSound(
      root["panelSound"], path: "panelSound", soundNames: soundNames, logLines: &logLines)
    file.waitingNotices = readBool(
      root["waitingNotices"], path: "waitingNotices",
      defaultValue: Settings.defaultWaitingNotices, logLines: &logLines)
    file.waitingNoticeDelay = readWaitingNoticeDelay(
      root["waitingNoticeDelay"], path: "waitingNoticeDelay", logLines: &logLines)
    file.waitingNoticeDuration = readWaitingNoticeDuration(
      root["waitingNoticeDuration"], path: "waitingNoticeDuration", logLines: &logLines)
    file.approvalCard = readApprovalCard(
      root["approvalCard"], path: "approvalCard", logLines: &logLines)
    file.approvalCardDelay = readApprovalCardDelay(
      root["approvalCardDelay"], path: "approvalCardDelay", logLines: &logLines)
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
    file.rules = readRules(root["rules"], path: "rules", logLines: &logLines)

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

    if let checkpointsValue = root["contextCheckpoints"] {
      let path = "contextCheckpoints"
      switch checkpointsValue {
      case .object(let object):
        file.contextCheckpoints = readContextCheckpointValues(
          object, path: path, allowsHosts: true, logLines: &logLines)
        file.contextCheckpointsClaude = readContextCheckpointHosts(
          object["hosts"], path: "\(path).hosts", logLines: &logLines)
      default:
        logLines.append("\(path): expected an object, ignored")
      }
    }

    return (file, logLines)
  }

  private static func readContextCheckpointHosts(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> ContextCheckpointFileValues? {
    guard let value else { return nil }
    guard case .object(let hostsObject) = value else {
      logLines.append("\(path): expected an object, ignored")
      return nil
    }
    for key in hostsObject.keys where Host(rawValue: key) == nil {
      logLines.append("unknown key \"\(path).\(key)\", ignored")
    }
    for host in Host.allCases where host != .claude && hostsObject[host.rawValue] != nil {
      logLines.append(
        "\(path).\(host.rawValue): context checkpoints support only Claude Code, ignored")
    }
    guard let claudeValue = hostsObject["claude"] else { return nil }
    guard case .object(let claudeObject) = claudeValue else {
      logLines.append("\(path).claude: expected an object, ignored")
      return nil
    }
    return readContextCheckpointValues(
      claudeObject, path: "\(path).claude", allowsHosts: false, logLines: &logLines)
  }

  private static func readContextCheckpointValues(
    _ object: [String: JSONValue], path: String, allowsHosts: Bool, logLines: inout [String]
  ) -> ContextCheckpointFileValues {
    for key in object.keys.sorted() {
      let known = contextCheckpointKeys.contains(key) && (allowsHosts || key != "hosts")
      if !known {
        logLines.append("unknown key \"\(path).\(key)\", ignored")
      }
    }
    var values = ContextCheckpointFileValues()
    values.enabled = readBool(
      object["enabled"], path: "\(path).enabled", defaultValue: false, logLines: &logLines)
    values.mode = readContextCheckpointMode(
      object["mode"], path: "\(path).mode", logLines: &logLines)
    if let thresholdsValue = object["thresholds"] {
      let thresholdsPath = "\(path).thresholds"
      if case .object(let thresholds) = thresholdsValue {
        for key in thresholds.keys.sorted() where key != "200k" && key != "1m" {
          logLines.append("unknown key \"\(thresholdsPath).\(key)\", ignored")
        }
        values.standardThresholds = readThresholdLadder(
          thresholds["200k"], path: "\(thresholdsPath).200k",
          defaultValue: ContextCheckpointSettings.defaultStandardThresholds, logLines: &logLines)
        values.millionThresholds = readThresholdLadder(
          thresholds["1m"], path: "\(thresholdsPath).1m",
          defaultValue: ContextCheckpointSettings.defaultMillionThresholds, logLines: &logLines)
      } else {
        logLines.append("\(thresholdsPath): expected an object, ignored")
      }
    }
    values.modelThresholds = readModelThresholds(
      object["modelThresholds"], path: "\(path).modelThresholds", logLines: &logLines)
    values.rearmBelow = readRearmBelow(
      object["rearmBelow"], path: "\(path).rearmBelow", logLines: &logLines)
    values.handoffFile = readHandoffFile(
      object["handoffFile"], path: "\(path).handoffFile", logLines: &logLines)
    values.notes = readContextCheckpointNotes(
      object["notes"], path: "\(path).notes", logLines: &logLines)
    values.menuBarMeter = readBool(
      object["menuBarMeter"], path: "\(path).menuBarMeter", defaultValue: false,
      logLines: &logLines)
    return values
  }

  private static func readContextCheckpointMode(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> ContextCheckpointMode? {
    guard let value else { return nil }
    guard let mode = value.stringValue.flatMap(ContextCheckpointMode.init(rawValue:)) else {
      logLines.append(
        "\(path): expected \"panel\" or \"silent\", using default"
          + " \"\(ContextCheckpointSettings.defaultMode.rawValue)\"")
      return nil
    }
    return mode
  }

  private static func ascendingLadder(_ value: JSONValue) -> [Int]? {
    guard case .array(let array) = value, array.count == 3 else { return nil }
    var ladder: [Int] = []
    for element in array {
      guard let tokens = integerValue(element), tokens >= 1 else { return nil }
      if let previous = ladder.last, tokens <= previous { return nil }
      ladder.append(tokens)
    }
    return ladder
  }

  private static func readThresholdLadder(
    _ value: JSONValue?, path: String, defaultValue: [Int], logLines: inout [String]
  ) -> [Int]? {
    guard let value else { return nil }
    guard let ladder = ascendingLadder(value) else {
      logLines.append(
        "\(path): expected 3 ascending whole numbers of tokens, using default \(defaultValue)")
      return nil
    }
    return ladder
  }

  private static func readModelThresholds(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> [String: [Int]]? {
    guard let value else { return nil }
    guard case .object(let object) = value else {
      logLines.append("\(path): expected an object, ignored")
      return nil
    }
    var ladders: [String: [Int]] = [:]
    for key in object.keys.sorted() {
      guard !key.isEmpty, let value = object[key], let ladder = ascendingLadder(value) else {
        logLines.append(
          "\(path).\(key): expected 3 ascending whole numbers of tokens, ignored")
        continue
      }
      ladders[key] = ladder
    }
    return ladders
  }

  private static func readRearmBelow(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> Double? {
    guard let value else { return nil }
    guard let number = numberValue(value),
      ContextCheckpointSettings.rearmBelowRange.contains(number)
    else {
      logLines.append(
        "\(path): expected a number from 0.1 to 0.95, using default"
          + " \(formatNumber(ContextCheckpointSettings.defaultRearmBelow))")
      return nil
    }
    return number
  }

  private static func readHandoffFile(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> String? {
    guard let value else { return nil }
    guard let string = value.stringValue, !string.isEmpty else {
      logLines.append(
        "\(path): expected a non-empty string, using default"
          + " \"\(ContextCheckpointSettings.defaultHandoffFile)\"")
      return nil
    }
    return string
  }

  private static func readContextCheckpointNotes(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> [String: String] {
    guard let value else { return [:] }
    guard case .object(let object) = value else {
      logLines.append("\(path): expected an object, ignored")
      return [:]
    }
    var notes: [String: String] = [:]
    for key in object.keys.sorted() {
      guard ContextCheckpointNotes.names.contains(key) else {
        logLines.append("unknown key \"\(path).\(key)\", ignored")
        continue
      }
      guard let text = object[key]?.stringValue, !text.isEmpty,
        text.count <= ContextCheckpointNotes.maximumLength
      else {
        logLines.append("\(path).\(key): expected text of 1 to 4000 characters, using the default")
        continue
      }
      notes[key] = text
    }
    return notes
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
        object["idleSeconds"], path: "\(path).idleSeconds", range: Settings.idleSecondsRange,
        defaultValue: Settings.defaultIdleSeconds, logLines: &logLines),
      graceSeconds: readNonNegativeNumber(
        object["graceSeconds"], path: "\(path).graceSeconds", range: Settings.graceSecondsRange,
        defaultValue: Settings.defaultGraceSeconds, logLines: &logLines),
      handoffApps: readHandoffApps(
        object["handoffApps"], path: "\(path).handoffApps", logLines: &logLines),
      snoozePresets: readSnoozePresets(
        object["snoozeMinutes"], path: "\(path).snoozeMinutes", logLines: &logLines),
      includeHeadlessSessions: readBool(
        object["includeHeadlessSessions"], path: "\(path).includeHeadlessSessions",
        defaultValue: Settings.defaultIncludeHeadlessSessions, logLines: &logLines),
      waitingNoticeDelay: readWaitingNoticeDelay(
        object["waitingNoticeDelay"], path: "\(path).waitingNoticeDelay",
        logLines: &logLines),
      approvalCard: readApprovalCard(
        object["approvalCard"], path: "\(path).approvalCard", logLines: &logLines),
      approvalCardDelay: readApprovalCardDelay(
        object["approvalCardDelay"], path: "\(path).approvalCardDelay", logLines: &logLines))
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

  static func durationValue(_ value: JSONValue, unit: TimeInterval) -> TimeInterval? {
    switch value {
    case .string(let text): return DurationText.parse(text, bareUnit: unit)
    default: return numberValue(value).map { $0 * unit }
    }
  }

  private static func writtenForm(_ value: JSONValue) -> String {
    switch value {
    case .string(let text): return "\"\(text)\""
    case .int(let intValue): return String(intValue)
    case .double(let doubleValue): return formatNumber(doubleValue)
    default: return "value"
    }
  }

  private static func readArmDelay(
    _ value: JSONValue?, path: String, defaultValue: Double, logLines: inout [String]
  ) -> Double? {
    guard let value else { return nil }
    guard let seconds = durationValue(value, unit: 1) else {
      logLines.append("\(path): not a number, using default \(formatNumber(defaultValue))")
      return nil
    }
    if !Settings.armDelayRange.contains(seconds) {
      let clamped = min(
        max(seconds, Settings.armDelayRange.lowerBound), Settings.armDelayRange.upperBound)
      logLines.append(
        "\(path): \(writtenForm(value)) is out of range 0...3, clamped to \(formatNumber(clamped))"
      )
      return clamped
    }
    return seconds
  }

  private static func readNonNegativeNumber(
    _ value: JSONValue?, path: String, range: ClosedRange<Double>, defaultValue: Double,
    logLines: inout [String]
  ) -> Double? {
    guard let value else { return nil }
    guard let seconds = durationValue(value, unit: 1), seconds >= 0 else {
      logLines.append(
        "\(path): not a non-negative number, using default \(formatNumber(defaultValue))")
      return nil
    }
    guard range.contains(seconds) else {
      logLines.append(
        "\(path): \(writtenForm(value)) is out of range \(formatNumber(range.lowerBound))...\(formatNumber(range.upperBound)),"
          + " using default \(formatNumber(defaultValue))")
      return nil
    }
    return seconds
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

  private static func readWaitingNoticeDelay(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> TimeInterval? {
    guard let value else { return nil }
    guard let seconds = durationValue(value, unit: 1),
      Settings.waitingNoticeDelayRange.contains(seconds)
    else {
      logLines.append(
        "\(path): expected a duration from"
          + " \(DurationText.compact(Settings.waitingNoticeDelayRange.lowerBound)) to"
          + " \(DurationText.compact(Settings.waitingNoticeDelayRange.upperBound)), using default"
          + " \(DurationText.compact(Settings.defaultWaitingNoticeDelay))")
      return nil
    }
    return seconds
  }

  private static func readWaitingNoticeDuration(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> TimeInterval? {
    guard let value else { return nil }
    guard let seconds = durationValue(value, unit: 1),
      Settings.waitingNoticeDurationRange.contains(seconds)
    else {
      logLines.append(
        "\(path): expected a duration from"
          + " \(DurationText.compact(Settings.waitingNoticeDurationRange.lowerBound)) to"
          + " \(DurationText.compact(Settings.waitingNoticeDurationRange.upperBound)), using"
          + " default \(DurationText.compact(Settings.defaultWaitingNoticeDuration))")
      return nil
    }
    return seconds
  }

  private static func readApprovalCard(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> Bool? {
    guard let value else { return nil }
    guard let bool = value.boolValue else {
      logLines.append("\(path): not a boolean, using the agent's default")
      return nil
    }
    return bool
  }

  private static func readApprovalCardDelay(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> Double? {
    guard let value else { return nil }
    guard let seconds = durationValue(value, unit: 1),
      Settings.approvalCardDelayRange.contains(seconds)
    else {
      logLines.append(
        "\(path): expected a duration from"
          + " \(DurationText.compact(Settings.approvalCardDelayRange.lowerBound)) to"
          + " \(DurationText.compact(Settings.approvalCardDelayRange.upperBound)), using default"
          + " \(DurationText.compact(Settings.defaultApprovalCardDelay))")
      return nil
    }
    return seconds
  }

  private static func readPanelSound(
    _ value: JSONValue?, path: String, soundNames: [String], logLines: inout [String]
  ) -> String? {
    guard let value else { return nil }
    guard let name = value.stringValue, PanelSound.isSilent(name) || soundNames.contains(name)
    else {
      logLines.append(
        "\(path): expected \"\(PanelSound.none)\" or the name of a system sound, using default"
          + " \"\(Settings.defaultPanelSound)\"")
      return nil
    }
    return name
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
      logLines.append("\(path): expected a non-empty string, ignoring it")
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

  private static let quietWindowKeys: Set<String> = ["days", "from", "to"]

  private static func readQuietHours(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> [QuietWindow]? {
    guard let value else { return nil }
    guard case .array(let array) = value else {
      logLines.append("\(path): not an array, using default []")
      return nil
    }
    var windows: [QuietWindow] = []
    for (index, element) in array.enumerated() {
      let entryPath = "\(path)[\(index)]"
      guard windows.count < QuietWindow.maximumCount else {
        logLines.append("\(entryPath): at most \(QuietWindow.maximumCount) windows, dropped")
        continue
      }
      guard let window = readQuietWindow(element, path: entryPath, logLines: &logLines) else {
        continue
      }
      windows.append(window)
    }
    return windows
  }

  private static func readQuietWindow(
    _ value: JSONValue, path: String, logLines: inout [String]
  ) -> QuietWindow? {
    guard case .object(let object) = value else {
      logLines.append("\(path): expected an object, dropped")
      return nil
    }
    for key in object.keys.sorted() where !quietWindowKeys.contains(key) {
      logLines.append("unknown key \"\(path).\(key)\", ignored")
    }
    guard case .array(let dayValues)? = object["days"] else {
      logLines.append("\(path).days: expected a list of days like \"mon\", dropped")
      return nil
    }
    var days: [QuietWeekday] = []
    for dayValue in dayValues {
      guard let day = dayValue.stringValue.flatMap(QuietWeekday.init(rawValue:)) else {
        logLines.append("\(path).days: expected \"mon\" to \"sun\", dropped")
        return nil
      }
      days.append(day)
    }
    guard let from = object["from"]?.stringValue, let to = object["to"]?.stringValue,
      let window = QuietWindow(days: days, from: from, to: to)
    else {
      logLines.append(
        "\(path): expected at least one day and different from and to times like \"19:00\","
          + " dropped")
      return nil
    }
    return window
  }

  private static let ruleKeys: Set<String> = [
    "decision", "agent", "project", "tool", "command", "message",
  ]

  private static func readRules(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> [ApprovalRule]? {
    guard let value else { return nil }
    guard case .array(let array) = value else {
      logLines.append("\(path): not an array, ignored")
      return nil
    }
    var rules: [ApprovalRule] = []
    for (index, element) in array.enumerated() {
      if let rule = readRule(element, path: "\(path)[\(index)]", logLines: &logLines) {
        rules.append(rule)
      }
    }
    return rules
  }

  static func rule(from value: JSONValue) -> ApprovalRule? {
    var discarded: [String] = []
    return readRule(value, path: "rules", logLines: &discarded)
  }

  private static func readRule(
    _ value: JSONValue, path: String, logLines: inout [String]
  ) -> ApprovalRule? {
    guard case .object(let object) = value else {
      logLines.append("\(path): expected an object, dropped")
      return nil
    }
    for key in object.keys.sorted() where !ruleKeys.contains(key) {
      logLines.append("unknown key \"\(path).\(key)\", ignored")
    }
    guard let decision = object["decision"]?.stringValue.flatMap(ApprovalRule.Decision.init)
    else {
      logLines.append("\(path).decision: expected \"allow\" or \"deny\", dropped")
      return nil
    }
    var agent: Host?
    if let agentValue = object["agent"] {
      guard let host = agentValue.stringValue.flatMap(Host.init) else {
        logLines.append(
          "\(path).agent: expected \"claude\", \"codex\", \"cursor\" or \"antigravity\", dropped")
        return nil
      }
      agent = host
    }
    var project: String?
    if let projectValue = object["project"] {
      guard let text = nonEmptyString(projectValue) else {
        logLines.append("\(path).project: expected a non-empty string, dropped")
        return nil
      }
      guard text.hasPrefix("/") || text.hasPrefix("~") else {
        logLines.append(
          "\(path).project: expected an absolute path or one starting with ~, dropped")
        return nil
      }
      project = text
    }
    var fields: [String: String] = [:]
    for key in ["tool", "command", "message"] {
      guard let fieldValue = object[key] else { continue }
      guard let text = nonEmptyString(fieldValue) else {
        logLines.append("\(path).\(key): expected a non-empty string, dropped")
        return nil
      }
      fields[key] = text
    }
    var message = fields["message"]
    if decision == .allow, message != nil {
      logLines.append("\(path).message: only used by deny rules, ignored")
      message = nil
    }
    return ApprovalRule(
      decision: decision, agent: agent, project: project, tool: fields["tool"],
      command: fields["command"], message: message)
  }

  private static func nonEmptyString(_ value: JSONValue) -> String? {
    guard let text = value.stringValue, !text.isEmpty else { return nil }
    return text
  }

  private static func readSnoozePresets(
    _ value: JSONValue?, path: String, logLines: inout [String]
  ) -> [TimeInterval]? {
    guard let value else { return nil }
    let fallback = Settings.defaultSnoozePresets.map(DurationText.compact).joined(separator: ", ")
    guard case .array(let array) = value, (1...6).contains(array.count) else {
      logLines.append("\(path): expected 1 to 6 durations, using default \(fallback)")
      return nil
    }
    var presets: [TimeInterval] = []
    for element in array {
      guard let seconds = durationValue(element, unit: 60),
        Settings.snoozePresetRange.contains(seconds)
      else {
        logLines.append(
          "\(path): expected durations from"
            + " \(DurationText.compact(Settings.snoozePresetRange.lowerBound)) to"
            + " \(DurationText.compact(Settings.snoozePresetRange.upperBound)), using default"
            + " \(fallback)")
        return nil
      }
      presets.append(seconds)
    }
    return presets
  }
}
