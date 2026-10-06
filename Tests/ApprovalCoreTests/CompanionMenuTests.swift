import Foundation
import Testing

@testable import ApprovalCore

@Suite struct CompanionMenuTests {
  private func input(
    isPaused: Bool = false,
    quietUntil: Date? = nil,
    pendingEntries: [WaitingEntry] = [],
    snoozePresets: [TimeInterval] = Settings.defaultSnoozePresets,
    launchAtLogin: LaunchAtLoginState = .notRegistered,
    sponsorURL: URL? = CompanionMenu.sponsorURL,
    buyMeACoffeeURL: URL? = nil,
    updateAvailable: UpdateAvailability? = nil,
    manualCheckResult: ManualUpdateCheckResult? = nil
  ) -> CompanionMenuInput {
    CompanionMenuInput(
      isPaused: isPaused,
      quietUntil: quietUntil,
      pendingEntries: pendingEntries,
      snoozePresets: snoozePresets,
      launchAtLogin: launchAtLogin,
      sponsorURL: sponsorURL,
      buyMeACoffeeURL: buyMeACoffeeURL,
      version: "0.1.0",
      updateAvailable: updateAvailable,
      manualCheckResult: manualCheckResult)
  }

  private func entries(
    _ input: CompanionMenuInput, timeZone: TimeZone = .gmt
  ) -> [CompanionMenuEntry] {
    CompanionMenu.items(for: input, timeZone: timeZone).compactMap { item in
      guard case .entry(let entry) = item, entry.title != "Recent Decisions" else { return nil }
      return entry
    }
  }

  private func decisionsEntry(
    _ input: CompanionMenuInput, timeZone: TimeZone = .gmt
  ) throws -> CompanionMenuEntry {
    let found = CompanionMenu.items(for: input, timeZone: timeZone).compactMap {
      item -> CompanionMenuEntry? in
      guard case .entry(let entry) = item, entry.title == "Recent Decisions" else { return nil }
      return entry
    }
    return try #require(found.first)
  }

  private func decision(
    _ index: Int, answer: DecisionAnswer, tool: String = "Bash", title: String = "git status"
  ) -> DecisionHistoryEntry {
    DecisionHistoryEntry(
      date: Date(timeIntervalSince1970: TimeInterval(14 * 3600 + 5 * 60 + index)), host: .claude,
      project: "shop-api", tool: tool, title: title, answer: answer)
  }

  @Test func recentDecisionsShowsOneDisabledRowWhenThereIsNoHistory() throws {
    let entry = try decisionsEntry(input())
    #expect(entry.isEnabled)
    #expect(
      entry.submenu == [.entry(CompanionMenuEntry(title: "No decisions yet", isEnabled: false))])
  }

  @Test func recentDecisionsListsDisabledRowsThenAClearHistoryAction() throws {
    var withHistory = input()
    withHistory.recentDecisions = [
      decision(0, answer: .approved),
      decision(1, answer: .denied, tool: "Edit", title: "App.swift"),
      decision(2, answer: .answeredInChat),
      decision(3, answer: .resolvedElsewhere),
      decision(
        4, answer: .compactAfterStep, tool: "Context checkpoint", title: "Context at 240K"),
    ]
    let entry = try decisionsEntry(withHistory)
    #expect(
      entry.submenu == [
        .entry(
          CompanionMenuEntry(
            title: "✓ Bash · shop-api · 14:05 — git status", isEnabled: false)),
        .entry(
          CompanionMenuEntry(
            title: "✕ Edit · shop-api · 14:05 — App.swift", isEnabled: false)),
        .entry(
          CompanionMenuEntry(
            title: "↩ Bash · shop-api · 14:05 — git status", isEnabled: false)),
        .entry(
          CompanionMenuEntry(
            title: "↩ Bash · shop-api · 14:05 — git status", isEnabled: false)),
        .entry(
          CompanionMenuEntry(
            title: "• Context checkpoint · shop-api · 14:05 — Context at 240K",
            isEnabled: false)),
        .separator,
        .entry(CompanionMenuEntry(title: "Clear History", action: .clearDecisionHistory)),
      ])
  }

  @Test func recentDecisionsShowsAtMostTenRows() throws {
    var withHistory = input()
    withHistory.recentDecisions = (0..<15).map { decision($0, answer: .approved) }
    let entry = try decisionsEntry(withHistory)
    #expect(entry.submenu.count == 12)
  }

  @Test func everyCheckpointAnswerGetsTheBullet() {
    for answer in [
      DecisionAnswer.continued, .compactAfterStep, .handOff, .notThisSession, .dismissed,
    ] {
      let title = CompanionMenu.decisionRowTitle(
        for: decision(0, answer: answer), timeZone: .gmt)
      #expect(title.hasPrefix("• "))
    }
  }

  @Test func ruleAnswersShowTheApprovedAndDeniedGlyphsAndRule() {
    #expect(
      CompanionMenu.decisionRowTitle(
        for: decision(0, answer: .allowedByRule, title: "pnpm lint"), timeZone: .gmt)
        == "✓ Bash · shop-api · rule · 14:05 — pnpm lint")
    #expect(
      CompanionMenu.decisionRowTitle(
        for: decision(0, answer: .deniedByRule, title: "rm -rf x"), timeZone: .gmt)
        == "✕ Bash · shop-api · rule · 14:05 — rm -rf x")
    #expect(
      CompanionMenu.decisionRowTitle(
        for: decision(0, answer: .approved, title: "pnpm lint"), timeZone: .gmt)
        == "✓ Bash · shop-api · 14:05 — pnpm lint")
  }

  @Test func recentDecisionsSitsBetweenPendingAndPause() {
    let titles = CompanionMenu.items(for: input(), timeZone: .gmt).compactMap { item -> String? in
      guard case .entry(let entry) = item else { return nil }
      return entry.title
    }
    #expect(titles[1] == "No requests pending")
    #expect(titles[2] == "Recent Decisions")
    #expect(titles[3] == "Pause Countersign")
  }

  private func entry(
    _ index: Int, of input: CompanionMenuInput, timeZone: TimeZone = .gmt
  ) throws -> CompanionMenuEntry {
    let all = entries(input, timeZone: timeZone)
    try #require(all.indices.contains(index))
    return all[index]
  }

  private static let quietUntil = Date(timeIntervalSince1970: 14 * 3600 + 5 * 60 + 59)

  @Test func contextEntryAppearsAfterPendingWithDisabledRowsOnlyWhenRowsExist() throws {
    let rows = [
      ContextMeterRow(
        sessionID: "a", project: "shop-api", tokens: 212_000, title: "shop-api · 212K tokens"),
      ContextMeterRow(
        sessionID: "b", project: "web", tokens: 90_000, title: "web · 90K tokens"),
    ]
    var withRows = input()
    withRows.contextRows = rows
    let entry = try entry(2, of: withRows)
    #expect(entry.title == "Context in live sessions")
    #expect(entry.isEnabled)
    #expect(
      entry.submenu == [
        .entry(CompanionMenuEntry(title: "shop-api · 212K tokens", isEnabled: false)),
        .entry(CompanionMenuEntry(title: "web · 90K tokens", isEnabled: false)),
      ])
    #expect(
      !entries(input()).contains { $0.title == "Context in live sessions" })
  }

  @Test func activeMenuListsEveryItemInOrder() throws {
    let sponsor = try #require(CompanionMenu.sponsorURL)
    let documentation = try #require(CompanionMenu.documentationURL)
    let askAQuestion = try #require(CompanionMenu.askAQuestionURL)
    let contactDeveloper = try #require(CompanionMenu.contactDeveloperURL)
    let items = CompanionMenu.items(for: input(), timeZone: .gmt)

    #expect(
      items == [
        .entry(CompanionMenuEntry(title: "Countersign is on", isEnabled: false)),
        .entry(CompanionMenuEntry(title: "No requests pending", isEnabled: false)),
        .entry(
          CompanionMenuEntry(
            title: "Recent Decisions",
            submenu: [.entry(CompanionMenuEntry(title: "No decisions yet", isEnabled: false))])),
        .separator,
        .entry(CompanionMenuEntry(title: "Pause Countersign", action: .pause)),
        .entry(
          CompanionMenuEntry(
            title: "Snooze",
            submenu: [
              .entry(CompanionMenuEntry(title: "Quiet for 1 minute", action: .snooze(seconds: 60))),
              .entry(CompanionMenuEntry(title: "5 minutes", action: .snooze(seconds: 300))),
              .entry(CompanionMenuEntry(title: "15 minutes", action: .snooze(seconds: 900))),
              .entry(CompanionMenuEntry(title: "30 minutes", action: .snooze(seconds: 1800))),
            ])),
        .separator,
        .entry(CompanionMenuEntry(title: "Settings…", keyEquivalent: ",", action: .openSettings)),
        .entry(CompanionMenuEntry(title: "Show a Test Panel", action: .showTestPanel(.command))),
        .entry(CompanionMenuEntry(title: "Launch at Login", action: .enableLaunchAtLogin)),
        .separator,
        .entry(
          CompanionMenuEntry(
            title: "Help",
            submenu: [
              .entry(CompanionMenuEntry(title: "Show the Tour", action: .showTour)),
              .entry(CompanionMenuEntry(title: "Documentation", action: .openURL(documentation))),
              .entry(CompanionMenuEntry(title: "Report a Problem…", action: .reportProblem)),
              .entry(
                CompanionMenuEntry(title: "Ask a Question…", action: .openURL(askAQuestion))),
              .entry(
                CompanionMenuEntry(
                  title: "Contact the Developer…", action: .openURL(contactDeveloper))),
            ])),
        .entry(CompanionMenuEntry(title: "Check for Updates…", action: .checkForUpdatesNow)),
        .separator,
        .entry(
          CompanionMenuEntry(
            title: "Support the Developer",
            submenu: [
              .entry(CompanionMenuEntry(title: "Sponsor on GitHub", action: .openURL(sponsor)))
            ])),
        .entry(CompanionMenuEntry(title: "Countersign 0.1.0", isEnabled: false)),
        .entry(CompanionMenuEntry(title: "Quit Countersign", keyEquivalent: "q", action: .quit)),
      ])
    #expect(CompanionMenu.icon(isPaused: false, quietUntil: nil) == .active)
  }

  @Test func documentationLinkPointsAtTheReadme() {
    #expect(
      CompanionMenu.documentationURL?.absoluteString
        == "https://github.com/Gord1y/countersign#readme")
  }

  @Test func askAQuestionLinkPointsAtTheQAndADiscussionCategory() {
    #expect(
      CompanionMenu.askAQuestionURL?.absoluteString
        == "https://github.com/Gord1y/countersign/discussions/new?category=q-a")
  }

  @Test func contactDeveloperLinkPointsAtTheWebsite() {
    #expect(CompanionMenu.contactDeveloperURL?.absoluteString == "https://www.gord1y.dev/")
  }

  @Test func helpSubmenuListsDocumentationReportAskAndContactInOrder() throws {
    let documentation = try #require(CompanionMenu.documentationURL)
    let askAQuestion = try #require(CompanionMenu.askAQuestionURL)
    let contactDeveloper = try #require(CompanionMenu.contactDeveloperURL)
    let help = try entry(7, of: input())

    #expect(help.title == "Help")
    #expect(
      help.submenu == [
        .entry(CompanionMenuEntry(title: "Show the Tour", action: .showTour)),
        .entry(CompanionMenuEntry(title: "Documentation", action: .openURL(documentation))),
        .entry(CompanionMenuEntry(title: "Report a Problem…", action: .reportProblem)),
        .entry(CompanionMenuEntry(title: "Ask a Question…", action: .openURL(askAQuestion))),
        .entry(
          CompanionMenuEntry(
            title: "Contact the Developer…", action: .openURL(contactDeveloper))),
      ])
  }

  @Test func sponsorLinkPointsAtGitHubSponsors() {
    #expect(CompanionMenu.sponsorURL?.absoluteString == "https://github.com/sponsors/Gord1y")
  }

  @Test func buyMeACoffeeLinkPointsAtGord1ysPage() {
    #expect(CompanionMenu.buyMeACoffeeURL?.absoluteString == "https://buymeacoffee.com/gord1y")
  }

  @Test func versionDefaultsToTheBinarysOwnVersion() throws {
    let defaulted = CompanionMenuInput(
      isPaused: false, quietUntil: nil, pendingEntries: [], snoozePresets: [60],
      launchAtLogin: .notRegistered)
    #expect(defaulted.version == CountersignVersion.current)
    #expect(defaulted.sponsorURL == CompanionMenu.sponsorURL)
    #expect(defaulted.buyMeACoffeeURL == CompanionMenu.buyMeACoffeeURL)
    #expect(defaulted.updateAvailable == nil)
    #expect(defaulted.manualCheckResult == nil)
    let version = try #require(entries(defaulted).dropLast(1).last)
    #expect(version.title == "Countersign \(CountersignVersion.current)")
    #expect(!version.isEnabled)
    let sponsor = try #require(CompanionMenu.sponsorURL)
    let coffee = try #require(CompanionMenu.buyMeACoffeeURL)
    let support = try #require(
      entries(defaulted).first(where: { $0.title == "Support the Developer" }))
    #expect(
      support.submenu == [
        .entry(CompanionMenuEntry(title: "Sponsor on GitHub", action: .openURL(sponsor))),
        .entry(CompanionMenuEntry(title: "Buy Me a Coffee", action: .openURL(coffee))),
      ])
  }

  @Test func pausedMenuOffersResume() throws {
    let paused = input(isPaused: true)

    #expect(try entry(0, of: paused) == CompanionMenuEntry(title: "Paused", isEnabled: false))
    #expect(
      try entry(2, of: paused) == CompanionMenuEntry(title: "Resume Countersign", action: .resume))
    #expect(CompanionMenu.icon(isPaused: true, quietUntil: nil) == .paused)
  }

  @Test func pausedMenuDisablesSnoozeWithNoSubmenu() throws {
    let paused = try entry(3, of: input(isPaused: true))

    #expect(paused == CompanionMenuEntry(title: "Snooze", isEnabled: false))
    #expect(paused.submenu.isEmpty)
  }

  @Test func quietMenuShowsTheEndTimeInLocalTimeAndOffersToEndIt() throws {
    let quiet = input(quietUntil: Self.quietUntil)

    #expect(try entry(0, of: quiet).title == "Quiet until 14:05")
    let plusThree = try #require(TimeZone(secondsFromGMT: 3 * 3600))
    #expect(try entry(0, of: quiet, timeZone: plusThree).title == "Quiet until 17:05")
    #expect(try entry(2, of: quiet).action == .pause)
    let snooze = try entry(3, of: quiet)
    #expect(
      snooze == CompanionMenuEntry(title: "End Quiet Time (until 14:05)", action: .endQuietTime))
    #expect(snooze.submenu.isEmpty)
    let inPlusThree = try entry(3, of: quiet, timeZone: plusThree)
    #expect(inPlusThree.title == "End Quiet Time (until 17:05)")
    #expect(CompanionMenu.icon(isPaused: false, quietUntil: Self.quietUntil) == .quiet)
  }

  @Test func pauseOutranksQuietTime() throws {
    let both = input(isPaused: true, quietUntil: Self.quietUntil)

    #expect(try entry(0, of: both).title == "Paused")
    #expect(try entry(2, of: both).action == .resume)
    #expect(try entry(3, of: both) == CompanionMenuEntry(title: "Snooze", isEnabled: false))
    #expect(try entry(3, of: both).submenu.isEmpty)
    #expect(CompanionMenu.icon(isPaused: true, quietUntil: Self.quietUntil) == .paused)
  }

  @Test func noPendingRequestsIsDisabledWithoutASubmenu() throws {
    let pending = try entry(1, of: input())

    #expect(pending == CompanionMenuEntry(title: "No requests pending", isEnabled: false))
    #expect(pending.submenu.isEmpty)
  }

  @Test func onePendingRequestListsItsRow() throws {
    let summary = TicketSummary(host: .claude, project: "shop-api", tool: "Bash", agentType: nil)
    let pending = try entry(1, of: input(pendingEntries: [WaitingEntry(summary: summary)]))

    #expect(
      pending
        == CompanionMenuEntry(
          title: "1 request pending",
          submenu: [
            .entry(CompanionMenuEntry(title: "Claude Code · shop-api · Bash", isEnabled: false))
          ]))
  }

  @Test func severalPendingRequestsListEveryRowOldestFirstIncludingUnreadableOnes() throws {
    let described = TicketSummary(
      host: .claude, project: "shop-api", tool: "Edit", agentType: "general-purpose",
      agentDescription: "Verify checkout totals")
    let typeOnly = TicketSummary(
      host: .codex, project: "other-api", tool: "apply_patch", agentType: "Explore")
    let emptyDescription = TicketSummary(
      host: .claude, project: "docs", tool: "Write", agentType: "Plan", agentDescription: "")
    let pending = try entry(
      1,
      of: input(pendingEntries: [
        WaitingEntry(summary: described),
        WaitingEntry(summary: nil),
        WaitingEntry(summary: typeOnly),
        WaitingEntry(summary: emptyDescription),
      ]))

    #expect(pending.title == "4 requests pending")
    #expect(pending.isEnabled)
    #expect(pending.action == nil)
    #expect(
      pending.submenu == [
        .entry(
          CompanionMenuEntry(
            title: "Claude Code · shop-api · Edit · Verify checkout totals", isEnabled: false)),
        .entry(CompanionMenuEntry(title: "Unknown request", isEnabled: false)),
        .entry(
          CompanionMenuEntry(title: "Codex · other-api · apply_patch · Explore", isEnabled: false)),
        .entry(CompanionMenuEntry(title: "Claude Code · docs · Write · Plan", isEnabled: false)),
      ])
  }

  @Test func aPendingRequestWithATicketOffersShowNowDenyAndAnswerInChat() throws {
    let summary = TicketSummary(host: .claude, project: "shop-api", tool: "Bash", agentType: nil)
    let pending = try entry(
      1, of: input(pendingEntries: [WaitingEntry(summary: summary, ticketID: "0001-42")]))

    #expect(
      pending.submenu == [
        .entry(
          CompanionMenuEntry(
            title: "Claude Code · shop-api · Bash",
            submenu: [
              .entry(
                CompanionMenuEntry(
                  title: "Show Now", action: .answerPending(ticketID: "0001-42", answer: .show))),
              .entry(
                CompanionMenuEntry(
                  title: "Deny", action: .answerPending(ticketID: "0001-42", answer: .deny))),
              .entry(
                CompanionMenuEntry(
                  title: "Answer in Chat",
                  action: .answerPending(ticketID: "0001-42", answer: .chat))),
            ]))
      ])
  }

  @Test func checkpointsAndUnreadableTicketsOfferOnlyShowNow() throws {
    let checkpoint = TicketSummary(
      host: .claude, project: "shop-api", tool: "Context checkpoint", agentType: nil,
      isContextCheckpoint: true)
    let pending = try entry(
      1,
      of: input(pendingEntries: [
        WaitingEntry(summary: checkpoint, ticketID: "0001-42"),
        WaitingEntry(summary: nil, ticketID: "0002-43"),
      ]))

    #expect(
      pending.submenu == [
        .entry(
          CompanionMenuEntry(
            title: "Claude Code · shop-api · Context checkpoint",
            submenu: [
              .entry(
                CompanionMenuEntry(
                  title: "Show Now", action: .answerPending(ticketID: "0001-42", answer: .show)))
            ])),
        .entry(
          CompanionMenuEntry(
            title: "Unknown request",
            submenu: [
              .entry(
                CompanionMenuEntry(
                  title: "Show Now", action: .answerPending(ticketID: "0002-43", answer: .show)))
            ])),
      ])
  }

  @Test func pendingRowsFollowTheQueueOrderAndKeepEachTicketsID() throws {
    let first = TicketSummary(host: .codex, project: "a", tool: "Bash", agentType: nil)
    let second = TicketSummary(host: .cursor, project: "b", tool: "Shell", agentType: nil)
    let pending = try entry(
      1,
      of: input(pendingEntries: [
        WaitingEntry(summary: second, ticketID: "0002-2"),
        WaitingEntry(summary: first, ticketID: "0001-1"),
      ]))

    let rows = pending.submenu.compactMap { item -> CompanionMenuEntry? in
      guard case .entry(let row) = item else { return nil }
      return row
    }
    #expect(rows.map(\.title) == ["Cursor · b · Shell", "Codex · a · Bash"])
    #expect(rows.allSatisfy { $0.isEnabled && $0.action == nil })
    let ids = rows.map { row in
      row.submenu.compactMap { item -> String? in
        guard case .entry(let action) = item,
          case .answerPending(let ticketID, _)? = action.action
        else { return nil }
        return ticketID
      }
    }
    #expect(ids == [["0002-2", "0002-2", "0002-2"], ["0001-1", "0001-1", "0001-1"]])
  }

  @Test func showATestPanelSitsRightAfterSettingsAndAsksForACommand() throws {
    let settings = try entry(4, of: input())
    let testPanel = try entry(5, of: input())

    #expect(settings.action == .openSettings)
    #expect(
      testPanel == CompanionMenuEntry(title: "Show a Test Panel", action: .showTestPanel(.command)))
    #expect(testPanel.isEnabled)
    #expect(testPanel.keyEquivalent.isEmpty)
    #expect(testPanel.submenu.isEmpty)
  }

  @Test func showATestPanelIsOfferedWhilePausedAndDuringQuietTime() throws {
    let paused = try entry(5, of: input(isPaused: true))
    let quiet = try entry(5, of: input(quietUntil: Self.quietUntil))

    #expect(paused.action == .showTestPanel(.command))
    #expect(paused.isEnabled)
    #expect(quiet.action == .showTestPanel(.command))
    #expect(quiet.isEnabled)
  }

  @Test func launchAtLoginEnabledIsCheckedAndUnregisters() throws {
    #expect(
      try entry(6, of: input(launchAtLogin: .enabled))
        == CompanionMenuEntry(
          title: "Launch at Login", isChecked: true, action: .disableLaunchAtLogin))
  }

  @Test func launchAtLoginNotRegisteredIsUncheckedAndRegisters() throws {
    #expect(
      try entry(6, of: input(launchAtLogin: .notRegistered))
        == CompanionMenuEntry(title: "Launch at Login", action: .enableLaunchAtLogin))
  }

  @Test func launchAtLoginRequiringApprovalOpensSystemSettings() throws {
    #expect(
      try entry(6, of: input(launchAtLogin: .requiresApproval))
        == CompanionMenuEntry(
          title: "Launch at Login (approve in System Settings)", action: .approveLaunchAtLogin))
  }

  @Test func launchAtLoginUnavailableIsDisabled() throws {
    #expect(
      try entry(6, of: input(launchAtLogin: .unavailable))
        == CompanionMenuEntry(title: "Launch at Login (unavailable)", isEnabled: false))
  }

  @Test func customSnoozePresetsKeepTheirOrderAndWording() throws {
    let snooze = try entry(3, of: input(snoozePresets: [120, 3600, 5400]))

    #expect(
      snooze.submenu == [
        .entry(CompanionMenuEntry(title: "Quiet for 2 minutes", action: .snooze(seconds: 120))),
        .entry(CompanionMenuEntry(title: "1 hour", action: .snooze(seconds: 3600))),
        .entry(CompanionMenuEntry(title: "90 minutes", action: .snooze(seconds: 5400))),
      ])
  }

  @Test func subMinuteSnoozePresetsReadInSeconds() throws {
    let snooze = try entry(3, of: input(snoozePresets: [30, 300]))

    #expect(
      snooze.submenu == [
        .entry(CompanionMenuEntry(title: "Quiet for 30 seconds", action: .snooze(seconds: 30))),
        .entry(CompanionMenuEntry(title: "5 minutes", action: .snooze(seconds: 300))),
      ])
  }

  @Test func snoozeWithNoPresetsAndNoQuietTimeIsDisabled() throws {
    #expect(
      try entry(3, of: input(snoozePresets: []))
        == CompanionMenuEntry(title: "Snooze", isEnabled: false))
  }

  @Test func snoozeWithNoPresetsDuringQuietTimeOnlyEndsIt() throws {
    #expect(
      try entry(3, of: input(quietUntil: Self.quietUntil, snoozePresets: []))
        == CompanionMenuEntry(title: "End Quiet Time (until 14:05)", action: .endQuietTime))
  }

  @Test func snoozePresetsComeFromTheTopLevelOfTheConfigFileOnly() {
    #expect(CompanionMenu.snoozePresets(for: ConfigFile()) == Settings.defaultSnoozePresets)
    #expect(CompanionMenu.snoozePresets(for: ConfigFile(snoozePresets: [180, 420])) == [180, 420])
    let hostOnly = ConfigFile(
      claude: ConfigFile.HostOverrides(snoozePresets: [600]),
      codex: ConfigFile.HostOverrides(snoozePresets: [1200]))
    #expect(CompanionMenu.snoozePresets(for: hostOnly) == Settings.defaultSnoozePresets)
    let both = ConfigFile(
      snoozePresets: [240], claude: ConfigFile.HostOverrides(snoozePresets: [600]))
    #expect(CompanionMenu.snoozePresets(for: both) == [240])
  }

  @Test func buyMeACoffeeIsHiddenUntilItHasALink() throws {
    let sponsor = try #require(CompanionMenu.sponsorURL)
    let coffee = try #require(URL(string: "https://buymeacoffee.com/example"))

    #expect(
      try entry(9, of: input()).submenu == [
        .entry(CompanionMenuEntry(title: "Sponsor on GitHub", action: .openURL(sponsor)))
      ])
    #expect(
      try entry(9, of: input(buyMeACoffeeURL: coffee)).submenu == [
        .entry(CompanionMenuEntry(title: "Sponsor on GitHub", action: .openURL(sponsor))),
        .entry(CompanionMenuEntry(title: "Buy Me a Coffee", action: .openURL(coffee))),
      ])
  }

  @Test func supportIsLeftOutWhenItHasNoLinks() {
    let titles = entries(input(sponsorURL: nil)).map(\.title)

    #expect(!titles.contains("Support the Developer"))
    #expect(titles.last == "Quit Countersign")
    #expect(titles.count == entries(input()).count - 1)
  }

  @Test func iconsAreTheAgreedSymbolsWithSpokenLabels() {
    #expect(CompanionIcon.active.symbolName == "checkmark.seal")
    #expect(CompanionIcon.paused.symbolName == "pause.circle")
    #expect(CompanionIcon.quiet.symbolName == "moon.zzz")
    #expect(CompanionIcon.active.accessibilityLabel == "Countersign")
    #expect(CompanionIcon.paused.accessibilityLabel == "Countersign, paused")
    #expect(CompanionIcon.quiet.accessibilityLabel == "Countersign, quiet time")
  }

  @Test func checkForUpdatesIsAlwaysPresentRightUnderHelp() throws {
    let help = try entry(7, of: input())
    let checkForUpdates = try entry(8, of: input())

    #expect(help.title == "Help")
    #expect(
      checkForUpdates
        == CompanionMenuEntry(
          title: "Check for Updates…", action: .checkForUpdatesNow))
  }

  @Test func updateAvailableAddsASubmenuAboveCheckForUpdates() throws {
    let releaseNotesURL = try #require(
      URL(string: "https://github.com/Gord1y/countersign/releases/tag/v0.2.0"))
    let availability = UpdateAvailability(
      version: "0.2.0", upgradeCommand: "brew upgrade countersign",
      releaseNotesURL: releaseNotesURL)

    let updateEntry = try entry(8, of: input(updateAvailable: availability))
    let checkForUpdates = try entry(9, of: input(updateAvailable: availability))
    let version = try #require(entries(input(updateAvailable: availability)).dropLast(1).last)

    #expect(updateEntry.title == "Update available: 0.2.0")
    #expect(
      updateEntry.submenu == [
        .entry(CompanionMenuEntry(title: "Open Release Notes", action: .openURL(releaseNotesURL))),
        .entry(
          CompanionMenuEntry(
            title: "Copy Upgrade Command",
            action: .copyUpgradeCommand("brew upgrade countersign"))),
      ])
    #expect(checkForUpdates.action == .checkForUpdatesNow)
    #expect(version.title == "Countersign 0.1.0")
  }

  @Test func updateAvailableWithNoReleaseNotesURLOnlyOffersToCopyTheCommand() throws {
    let availability = UpdateAvailability(
      version: "0.2.0", upgradeCommand: "curl -fsSL https://example.com/install.sh | sh",
      releaseNotesURL: nil)

    let updateEntry = try entry(8, of: input(updateAvailable: availability))

    #expect(
      updateEntry.submenu == [
        .entry(
          CompanionMenuEntry(
            title: "Copy Upgrade Command",
            action: .copyUpgradeCommand("curl -fsSL https://example.com/install.sh | sh")))
      ])
  }

  @Test func manualCheckUpToDateShowsADisabledLineAboveCheckForUpdates() throws {
    let manualResult = try entry(8, of: input(manualCheckResult: .upToDate))

    #expect(
      manualResult == CompanionMenuEntry(title: "Countersign is up to date", isEnabled: false))
  }

  @Test func manualCheckFailedShowsADisabledLineAboveCheckForUpdates() throws {
    let manualResult = try entry(8, of: input(manualCheckResult: .failed))

    #expect(
      manualResult
        == CompanionMenuEntry(title: "Couldn't check for updates", isEnabled: false))
  }

  @Test func updateAvailableTakesPrecedenceOverAManualCheckResult() throws {
    let availability = UpdateAvailability(
      version: "0.2.0", upgradeCommand: "brew upgrade countersign", releaseNotesURL: nil)

    let updateEntry = try entry(
      8, of: input(updateAvailable: availability, manualCheckResult: .upToDate))

    #expect(updateEntry.title == "Update available: 0.2.0")
  }

  @Test func pendingRowTitleMatchesTheWaitingListRow() {
    let summary = TicketSummary(
      host: .codex, project: "shop-api", tool: "Bash", agentType: "Explore",
      agentDescription: "Find the flaky test")

    #expect(
      CompanionMenu.pendingRowTitle(for: WaitingEntry(summary: summary))
        == "Codex · shop-api · Bash · Find the flaky test")
    #expect(CompanionMenu.pendingRowTitle(for: WaitingEntry(summary: nil)) == "Unknown request")
  }
}
