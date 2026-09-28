import Testing

@testable import ApprovalCore

@Suite struct PreferenceNameTextTests {
  @Test func titlesEveryRow() {
    #expect(
      PreferenceName.allCases.map(\.title) == [
        "Arm delay", "Arm delay after an answer", "Wait for idle", "Grace period",
        "Snooze presets", "Hand off when frontmost", "Check for updates", "Notes on answers",
        "When Countersign quits", "Mode after a plan", "Appearance", "Accent colour", "Open with",
      ])
  }

  @Test func captionsEveryRow() {
    #expect(
      PreferenceName.allCases.map(\.caption) == [
        "How long a new panel ignores keys and clicks.",
        "How long the next panel ignores keys and clicks.",
        "Quiet keyboard and mouse needed before a panel shows.",
        "Time a request may resolve elsewhere before it queues.",
        "Minutes offered by the Snooze menu, in order.",
        "No panel while the asking app is one of these and in front.",
        "Look for a newer Countersign release.",
        "Offer a note under Claude's questions, sent with the option you pick.",
        "Whether panels keep appearing after you quit the menu-bar app.",
        "What Claude Code switches to when you approve its plan.",
        "Light or dark for panels and Settings, or follow macOS.",
        "The colour of Approve and highlights on panels and in Settings.",
        "The app Open in Editor uses for config.json.",
      ])
  }

  @Test func givesEveryRowItsOwnTitle() {
    #expect(Set(PreferenceName.allCases.map(\.title)).count == PreferenceName.allCases.count)
  }

  @Test func explainsEveryRow() {
    for name in PreferenceName.allCases {
      #expect(!name.explanation.isEmpty)
    }
  }

  @Test func idleSecondsCountsFromLastInputNotArrival() {
    #expect(PreferenceName.idleSeconds.explanation.contains("last input"))
  }

  @Test func graceSecondsAlwaysStartsAtArrival() {
    #expect(PreferenceName.graceSeconds.explanation.contains("arrival"))
  }

  @Test func defaultTextMatchesTheBuiltInDefaults() {
    #expect(PreferenceName.armDelay.defaultText == "0.8 seconds")
    #expect(PreferenceName.chainedArmDelay.defaultText == "0.1 seconds")
    #expect(PreferenceName.idleSeconds.defaultText == "5 seconds")
    #expect(PreferenceName.graceSeconds.defaultText == "0 seconds")
    #expect(PreferenceName.snoozeMinutes.defaultText == "1, 5, 15 and 30 minutes")
    #expect(PreferenceName.handoffApps.defaultText == "No apps")
    #expect(PreferenceName.checkForUpdates.defaultText == "Off")
    #expect(PreferenceName.questionNotes.defaultText == "Off")
    #expect(PreferenceName.quitBehavior.defaultText == "Ask")
    #expect(PreferenceName.modeAfterPlan.defaultText == "Ask before edits")
    #expect(PreferenceName.appearance.defaultText == "System")
    #expect(PreferenceName.accentColor.defaultText == "Amber")
    #expect(PreferenceName.editorApp.defaultText == "Default app")
  }

  @Test func namesEveryAppearanceChoice() {
    #expect(AppearanceChoice.allCases.map(\.rawValue) == ["system", "light", "dark"])
    #expect(AppearanceChoice.allCases.map(\.title) == ["System", "Light", "Dark"])
  }

  @Test func namesEveryPlanApprovalMode() {
    #expect(
      PlanApprovalMode.allCases.map(\.title) == ["Ask before edits", "Accept edits", "Auto"])
  }
}
