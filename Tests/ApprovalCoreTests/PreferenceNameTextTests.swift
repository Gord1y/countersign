import Testing

@testable import ApprovalCore

@Suite struct PreferenceNameTextTests {
  @Test func titlesEveryRow() {
    #expect(
      PreferenceName.allCases.prefix(15).map(\.title) == [
        "Arm delay", "Arm delay after an answer", "Wait for idle", "Grace period",
        "Snooze presets", "Quiet hours", "Hand off when frontmost", "Check for updates",
        "Notes on answers",
        "When Countersign quits", "Mode after a plan", "Appearance", "Accent colour",
        "Skills in the sidebar", "Open with",
      ])
  }

  @Test func captionsEveryRow() {
    #expect(
      PreferenceName.allCases.prefix(15).map(\.caption) == [
        "How long a new panel ignores keys and clicks.",
        "How long the next panel ignores keys and clicks.",
        "Quiet keyboard and mouse needed before a panel shows.",
        "Time a request may resolve elsewhere before it queues.",
        "Durations offered by the Snooze menu, in order.",
        "Recurring times when panels wait, like a snooze that repeats.",
        "No panel while the asking app is one of these and in front.",
        "Look for a newer Countersign release.",
        "Offer a note under Claude's questions, sent with the option you pick.",
        "Whether panels keep appearing after you quit the menu-bar app.",
        "What Claude Code switches to when you approve its plan.",
        "Light or dark for panels and Settings, or follow macOS.",
        "The colour of Approve and highlights on panels and in Settings.",
        "Show the Skills group in the sidebar.",
        "The app Open in Editor uses for config.json.",
      ])
  }

  @Test func titlesEveryContextRow() {
    #expect(
      PreferenceName.allCases.suffix(13).map(\.title) == [
        "Context checkpoints (Claude Code)", "Checkpoint style", "Checkpoints, 200K window",
        "Checkpoints, 1M window", "Checkpoints for one model", "Start over below", "Handoff file",
        "Soft note", "Status note", "Insist note", "Compact note", "Handoff note",
        "Context in the menu bar",
      ])
  }

  @Test func captionsEveryContextRow() {
    #expect(
      PreferenceName.allCases.suffix(13).map(\.caption) == [
        "Nudge long Claude Code sessions toward a deliberate compaction.",
        "Show a panel, or add the note silently.",
        "Soft, status and insist, in tokens.",
        "Soft, status and insist, in tokens.",
        "A ladder for model IDs starting with a prefix.",
        "A drop this far below the peak counts as a fresh start.",
        "Where Claude writes a handoff, relative to the project.",
        "Sent in silent mode at the first checkpoint.",
        "Sent in silent mode at the second checkpoint.",
        "Sent in silent mode at the third checkpoint.",
        "Sent when you choose Compact after this step.",
        "Sent when you choose Hand off & start fresh.",
        "List each live session's context in the menu.",
      ])
  }

  @Test func givesEveryRowANonEmptyExplanationAndDefaultText() {
    for name in PreferenceName.allCases {
      #expect(!name.explanation.isEmpty)
      #expect(!name.defaultText.isEmpty)
    }
  }

  @Test func contextDefaultTextMatchesTheBuiltInDefaults() {
    #expect(PreferenceName.contextCheckpointsEnabled.defaultText == "On")
    #expect(PreferenceName.contextMode.defaultText == "Panel")
    #expect(PreferenceName.contextStandardThresholds.defaultText == "100K, 130K, 160K")
    #expect(PreferenceName.contextMillionThresholds.defaultText == "200K, 300K, 400K")
    #expect(PreferenceName.contextRearmBelow.defaultText == "60%")
    #expect(PreferenceName.contextHandoffFile.defaultText == "notes/handoff.md")
    #expect(PreferenceName.contextMenuBarMeter.defaultText == "Off")
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
    #expect(PreferenceName.armDelay.defaultText == "0.5 seconds")
    #expect(PreferenceName.chainedArmDelay.defaultText == "0.1 seconds")
    #expect(PreferenceName.idleSeconds.defaultText == "5 seconds")
    #expect(PreferenceName.graceSeconds.defaultText == "0 seconds")
    #expect(PreferenceName.snoozeMinutes.defaultText == "1, 5, 15 and 30 minutes")
    #expect(PreferenceName.handoffApps.defaultText == "No apps")
    #expect(PreferenceName.checkForUpdates.defaultText == "Off")
    #expect(PreferenceName.showSkills.defaultText == "On")
    #expect(PreferenceName.showSkills.title == "Skills in the sidebar")
    #expect(
      PreferenceName.showSkills.explanation
        == "Show the Skills group, which lists what countersign-skills installed. Turn it off to"
        + " hide the group.")
    #expect(PreferenceName.questionNotes.defaultText == "Off")
    #expect(PreferenceName.quitBehavior.defaultText == "Ask")
    #expect(PreferenceName.modeAfterPlan.defaultText == "Ask before edits")
    #expect(PreferenceName.appearance.defaultText == "System")
    #expect(PreferenceName.accentColor.defaultText == "Amber")
    #expect(PreferenceName.editorApp.defaultText == "Ask every time")
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
