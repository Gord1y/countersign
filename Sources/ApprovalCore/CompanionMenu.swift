import Foundation

public enum CompanionIcon: Sendable, Equatable {
  case active
  case paused
  case quiet

  public var symbolName: String {
    switch self {
    case .active: return "checkmark.seal"
    case .paused: return "pause.circle"
    case .quiet: return "moon.zzz"
    }
  }

  public var accessibilityLabel: String {
    switch self {
    case .active: return "Countersign"
    case .paused: return "Countersign, paused"
    case .quiet: return "Countersign, quiet time"
    }
  }
}

public enum LaunchAtLoginState: Sendable, Equatable {
  case enabled
  case notRegistered
  case requiresApproval
  case unavailable
}

public enum CompanionMenuAction: Sendable, Equatable {
  case pause
  case resume
  case snooze(seconds: TimeInterval)
  case endQuietTime
  case openSettings
  case showTestPanel(TestPanelKind)
  case enableLaunchAtLogin
  case disableLaunchAtLogin
  case approveLaunchAtLogin
  case openURL(URL)
  case setUp
  case reportProblem
  case checkForUpdatesNow
  case copyUpgradeCommand(String)
  case clearDecisionHistory
  case answerPending(ticketID: String, answer: MenuAnswer)
  case quit
}

public struct UpdateAvailability: Sendable, Equatable {
  public var version: String
  public var upgradeCommand: String
  public var releaseNotesURL: URL?

  public init(version: String, upgradeCommand: String, releaseNotesURL: URL?) {
    self.version = version
    self.upgradeCommand = upgradeCommand
    self.releaseNotesURL = releaseNotesURL
  }
}

public enum ManualUpdateCheckResult: Sendable, Equatable {
  case upToDate
  case failed
}

public struct CompanionMenuEntry: Sendable, Equatable {
  public var title: String
  public var isEnabled: Bool
  public var isChecked: Bool
  public var keyEquivalent: String
  public var action: CompanionMenuAction?
  public var submenu: [CompanionMenuItem]

  public init(
    title: String,
    isEnabled: Bool = true,
    isChecked: Bool = false,
    keyEquivalent: String = "",
    action: CompanionMenuAction? = nil,
    submenu: [CompanionMenuItem] = []
  ) {
    self.title = title
    self.isEnabled = isEnabled
    self.isChecked = isChecked
    self.keyEquivalent = keyEquivalent
    self.action = action
    self.submenu = submenu
  }
}

public enum CompanionMenuItem: Sendable, Equatable {
  case entry(CompanionMenuEntry)
  case separator
}

public struct CompanionMenuInput: Sendable, Equatable {
  public var isPaused: Bool
  public var quietUntil: Date?
  public var pendingEntries: [WaitingEntry]
  public var snoozePresets: [TimeInterval]
  public var launchAtLogin: LaunchAtLoginState
  public var sponsorURL: URL?
  public var buyMeACoffeeURL: URL?
  public var version: String
  public var updateAvailable: UpdateAvailability?
  public var manualCheckResult: ManualUpdateCheckResult?
  public var contextRows: [ContextMeterRow]
  public var recentDecisions: [DecisionHistoryEntry]

  public init(
    isPaused: Bool,
    quietUntil: Date?,
    pendingEntries: [WaitingEntry],
    snoozePresets: [TimeInterval],
    launchAtLogin: LaunchAtLoginState,
    sponsorURL: URL? = CompanionMenu.sponsorURL,
    buyMeACoffeeURL: URL? = CompanionMenu.buyMeACoffeeURL,
    version: String = CountersignVersion.current,
    updateAvailable: UpdateAvailability? = nil,
    manualCheckResult: ManualUpdateCheckResult? = nil,
    contextRows: [ContextMeterRow] = [],
    recentDecisions: [DecisionHistoryEntry] = []
  ) {
    self.contextRows = contextRows
    self.recentDecisions = recentDecisions
    self.isPaused = isPaused
    self.quietUntil = quietUntil
    self.pendingEntries = pendingEntries
    self.snoozePresets = snoozePresets
    self.launchAtLogin = launchAtLogin
    self.sponsorURL = sponsorURL
    self.buyMeACoffeeURL = buyMeACoffeeURL
    self.version = version
    self.updateAvailable = updateAvailable
    self.manualCheckResult = manualCheckResult
  }
}

public enum CompanionMenu {
  public static let sponsorURL = URL(string: "https://github.com/sponsors/Gord1y")
  public static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/gord1y")
  public static let documentationURL = URL(string: "https://github.com/Gord1y/countersign#readme")
  public static let askAQuestionURL = URL(
    string: "https://github.com/Gord1y/countersign/discussions/new?category=q-a")
  public static let contactDeveloperURL = URL(string: "https://www.gord1y.dev/")

  public static func icon(isPaused: Bool, quietUntil: Date?) -> CompanionIcon {
    CountersignStatus.current(pause: isPaused ? .paused : .active, quietUntil: quietUntil).icon
  }

  public static func snoozePresets(for file: ConfigFile) -> [TimeInterval] {
    file.snoozePresets ?? Settings.defaultSnoozePresets
  }

  public static func items(
    for input: CompanionMenuInput, timeZone: TimeZone = .current
  ) -> [CompanionMenuItem] {
    var items: [CompanionMenuItem] = [
      .entry(CompanionMenuEntry(title: statusTitle(input, timeZone: timeZone), isEnabled: false)),
      .entry(pendingEntry(input.pendingEntries)),
    ]
    if !input.contextRows.isEmpty {
      items.append(.entry(contextEntry(input.contextRows)))
    }
    items.append(
      .entry(decisionsEntry(input.recentDecisions, timeZone: timeZone)))
    items += [
      .separator,
      .entry(pauseEntry(isPaused: input.isPaused)),
      .entry(
        snoozeEntry(
          presets: input.snoozePresets, isPaused: input.isPaused, quietUntil: input.quietUntil,
          timeZone: timeZone)),
      .separator,
      .entry(CompanionMenuEntry(title: "Settings…", keyEquivalent: ",", action: .openSettings)),
      .entry(CompanionMenuEntry(title: "Show a Test Panel", action: .showTestPanel(.command))),
      .entry(launchAtLoginEntry(input.launchAtLogin)),
      .separator,
      .entry(helpEntry()),
    ]
    if let updateAvailable = input.updateAvailable {
      items.append(.entry(updateAvailableEntry(updateAvailable)))
    } else if let manualCheckResult = input.manualCheckResult {
      items.append(.entry(manualCheckResultEntry(manualCheckResult)))
    }
    items.append(
      .entry(CompanionMenuEntry(title: "Check for Updates…", action: .checkForUpdatesNow)))
    items.append(.separator)
    if let support = supportEntry(
      sponsorURL: input.sponsorURL, buyMeACoffeeURL: input.buyMeACoffeeURL)
    {
      items.append(.entry(support))
    }
    items += [
      .entry(CompanionMenuEntry(title: "Countersign \(input.version)", isEnabled: false)),
      .entry(CompanionMenuEntry(title: "Quit Countersign", keyEquivalent: "q", action: .quit)),
    ]
    return items
  }

  public static func pendingRowTitle(for entry: WaitingEntry) -> String {
    guard let summary = entry.summary else { return "Unknown request" }
    var parts = [summary.host.displayName, summary.project, summary.tool]
    if let agentLabel = summary.agentLabel {
      parts.append(agentLabel)
    }
    return parts.joined(separator: " · ")
  }

  private static func statusTitle(_ input: CompanionMenuInput, timeZone: TimeZone) -> String {
    CountersignStatus.current(
      pause: input.isPaused ? .paused : .active, quietUntil: input.quietUntil
    ).title(timeZone: timeZone)
  }

  private static func pendingEntry(_ entries: [WaitingEntry]) -> CompanionMenuEntry {
    switch entries.count {
    case 0:
      return CompanionMenuEntry(title: "No requests pending", isEnabled: false)
    case 1:
      return CompanionMenuEntry(title: "1 request pending", submenu: pendingRows(entries))
    default:
      return CompanionMenuEntry(
        title: "\(entries.count) requests pending", submenu: pendingRows(entries))
    }
  }

  private static func contextEntry(_ rows: [ContextMeterRow]) -> CompanionMenuEntry {
    CompanionMenuEntry(
      title: "Context in live sessions",
      submenu: rows.map { .entry(CompanionMenuEntry(title: $0.title, isEnabled: false)) })
  }

  public static let recentDecisionLimit = 10

  public static func decisionRowTitle(
    for entry: DecisionHistoryEntry, timeZone: TimeZone = .current
  ) -> String {
    let time = TimeOfDayText.describe(entry.date, timeZone: timeZone)
    let ruleMarker =
      entry.answer == .allowedByRule || entry.answer == .deniedByRule ? " · rule" : ""
    return
      "\(decisionGlyph(entry.answer)) \(entry.tool) · \(entry.project)\(ruleMarker) · \(time) — \(entry.title)"
  }

  private static func decisionGlyph(_ answer: DecisionAnswer) -> String {
    switch answer {
    case .approved, .allowedByRule: return "✓"
    case .denied, .deniedByRule: return "✕"
    case .answeredInChat, .resolvedElsewhere: return "↩"
    case .continued, .compactAfterStep, .handOff, .notThisSession, .dismissed: return "•"
    }
  }

  private static func decisionsEntry(_ entries: [DecisionHistoryEntry], timeZone: TimeZone)
    -> CompanionMenuEntry
  {
    guard !entries.isEmpty else {
      return CompanionMenuEntry(
        title: "Recent Decisions",
        submenu: [.entry(CompanionMenuEntry(title: "No decisions yet", isEnabled: false))])
    }
    var submenu: [CompanionMenuItem] = entries.prefix(recentDecisionLimit).map {
      .entry(
        CompanionMenuEntry(
          title: decisionRowTitle(for: $0, timeZone: timeZone), isEnabled: false))
    }
    submenu.append(.separator)
    submenu.append(
      .entry(CompanionMenuEntry(title: "Clear History", action: .clearDecisionHistory)))
    return CompanionMenuEntry(title: "Recent Decisions", submenu: submenu)
  }

  private static func pendingRows(_ entries: [WaitingEntry]) -> [CompanionMenuItem] {
    entries.map { .entry(pendingRow($0)) }
  }

  private static func pendingRow(_ entry: WaitingEntry) -> CompanionMenuEntry {
    let title = pendingRowTitle(for: entry)
    guard let ticketID = entry.ticketID else {
      return CompanionMenuEntry(title: title, isEnabled: false)
    }
    let answers: [CompanionMenuItem] = MenuAnswer.offered(for: entry.summary).map {
      .entry(
        CompanionMenuEntry(title: $0.title, action: .answerPending(ticketID: ticketID, answer: $0)))
    }
    return CompanionMenuEntry(title: title, submenu: answers)
  }

  private static func pauseEntry(isPaused: Bool) -> CompanionMenuEntry {
    isPaused
      ? CompanionMenuEntry(title: "Resume Countersign", action: .resume)
      : CompanionMenuEntry(title: "Pause Countersign", action: .pause)
  }

  private static func snoozeEntry(
    presets: [TimeInterval], isPaused: Bool, quietUntil: Date?, timeZone: TimeZone
  ) -> CompanionMenuEntry {
    if isPaused {
      return CompanionMenuEntry(title: "Snooze", isEnabled: false)
    }
    if let quietUntil {
      return CompanionMenuEntry(
        title: "End Quiet Time (until \(TimeOfDayText.describe(quietUntil, timeZone: timeZone)))",
        action: .endQuietTime)
    }
    let submenu: [CompanionMenuItem] = presets.enumerated().map { index, value in
      .entry(
        CompanionMenuEntry(
          title: SnoozeTitle.describe(seconds: value, isFirst: index == 0),
          action: .snooze(seconds: value)))
    }
    return CompanionMenuEntry(title: "Snooze", isEnabled: !submenu.isEmpty, submenu: submenu)
  }

  private static func launchAtLoginEntry(_ state: LaunchAtLoginState) -> CompanionMenuEntry {
    switch state {
    case .enabled:
      return CompanionMenuEntry(
        title: "Launch at Login", isChecked: true, action: .disableLaunchAtLogin)
    case .notRegistered:
      return CompanionMenuEntry(title: "Launch at Login", action: .enableLaunchAtLogin)
    case .requiresApproval:
      return CompanionMenuEntry(
        title: "Launch at Login (approve in System Settings)", action: .approveLaunchAtLogin)
    case .unavailable:
      return CompanionMenuEntry(title: "Launch at Login (unavailable)", isEnabled: false)
    }
  }

  private static func helpEntry() -> CompanionMenuEntry {
    var submenu: [CompanionMenuItem] = [
      .entry(CompanionMenuEntry(title: "Set Up…", action: .setUp))
    ]
    if let documentationURL {
      submenu.append(
        .entry(CompanionMenuEntry(title: "Documentation", action: .openURL(documentationURL))))
    }
    submenu.append(
      .entry(CompanionMenuEntry(title: "Report a Problem…", action: .reportProblem)))
    if let askAQuestionURL {
      submenu.append(
        .entry(CompanionMenuEntry(title: "Ask a Question…", action: .openURL(askAQuestionURL))))
    }
    if let contactDeveloperURL {
      submenu.append(
        .entry(
          CompanionMenuEntry(
            title: "Contact the Developer…", action: .openURL(contactDeveloperURL))))
    }
    return CompanionMenuEntry(title: "Help", submenu: submenu)
  }

  private static func supportEntry(sponsorURL: URL?, buyMeACoffeeURL: URL?)
    -> CompanionMenuEntry?
  {
    var submenu: [CompanionMenuItem] = []
    if let sponsorURL {
      submenu.append(
        .entry(CompanionMenuEntry(title: "Sponsor on GitHub", action: .openURL(sponsorURL))))
    }
    if let buyMeACoffeeURL {
      submenu.append(
        .entry(CompanionMenuEntry(title: "Buy Me a Coffee", action: .openURL(buyMeACoffeeURL))))
    }
    guard !submenu.isEmpty else { return nil }
    return CompanionMenuEntry(title: "Support the Developer", submenu: submenu)
  }

  private static func updateAvailableEntry(_ availability: UpdateAvailability)
    -> CompanionMenuEntry
  {
    var submenu: [CompanionMenuItem] = []
    if let releaseNotesURL = availability.releaseNotesURL {
      submenu.append(
        .entry(CompanionMenuEntry(title: "Open Release Notes", action: .openURL(releaseNotesURL))))
    }
    submenu.append(
      .entry(
        CompanionMenuEntry(
          title: "Copy Upgrade Command",
          action: .copyUpgradeCommand(availability.upgradeCommand))))
    return CompanionMenuEntry(title: "Update available: \(availability.version)", submenu: submenu)
  }

  private static func manualCheckResultEntry(_ result: ManualUpdateCheckResult)
    -> CompanionMenuEntry
  {
    switch result {
    case .upToDate:
      return CompanionMenuEntry(title: "Countersign is up to date", isEnabled: false)
    case .failed:
      return CompanionMenuEntry(title: "Couldn't check for updates", isEnabled: false)
    }
  }
}
