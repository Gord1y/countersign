import Foundation

extension PreferenceName {
  public var title: String {
    switch self {
    case .armDelay: return "Arm delay"
    case .chainedArmDelay: return "Arm delay after an answer"
    case .idleSeconds: return "Wait for idle"
    case .graceSeconds: return "Grace period"
    case .snoozeMinutes: return "Snooze presets"
    case .quietHours: return "Quiet hours"
    case .handoffApps: return "Hand off when frontmost"
    case .checkForUpdates: return "Check for updates"
    case .questionNotes: return "Notes on answers"
    case .quitBehavior: return "When Countersign quits"
    case .modeAfterPlan: return "Mode after a plan"
    case .panelSound: return "Sound"
    case .waitingNotices: return "Waiting-agent notices"
    case .waitingNoticeDelay: return "Notice after"
    case .waitingNoticeDuration: return "Show notice for"
    case .approvalCard: return "Approval card"
    case .approvalCardDelay: return "Show card after"
    case .appearance: return "Appearance"
    case .accentColor: return "Accent colour"
    case .editorApp: return "Open with"
    case .contextCheckpointsEnabled: return "Context checkpoints (Claude Code)"
    case .contextMode: return "Checkpoint style"
    case .contextStandardThresholds: return "Checkpoints, 200K window"
    case .contextMillionThresholds: return "Checkpoints, 1M window"
    case .contextModelThresholds: return "Checkpoints for one model"
    case .contextRearmBelow: return "Start over below"
    case .contextHandoffFile: return "Handoff file"
    case .contextNoteSoft: return "Soft note"
    case .contextNoteStatus: return "Status note"
    case .contextNoteInsist: return "Insist note"
    case .contextNoteCompact: return "Compact note"
    case .contextNoteHandoff: return "Handoff note"
    case .contextMenuBarMeter: return "Context in the menu bar"
    }
  }

  public var caption: String {
    switch self {
    case .armDelay: return "How long a new panel ignores keys and clicks."
    case .chainedArmDelay: return "How long the next panel ignores keys and clicks."
    case .idleSeconds: return "Quiet keyboard and mouse needed before a panel shows."
    case .graceSeconds: return "Time a request may resolve elsewhere before it queues."
    case .snoozeMinutes: return "Durations offered by the Snooze menu, in order."
    case .quietHours: return "Recurring times when panels wait, like a snooze that repeats."
    case .handoffApps: return "No panel while the asking app is one of these and in front."
    case .checkForUpdates: return "Look for a newer Countersign release."
    case .questionNotes:
      return "Offer a note under Claude's questions, sent with the option you pick."
    case .quitBehavior: return "Whether panels keep appearing after you quit the menu-bar app."
    case .modeAfterPlan: return "What Claude Code switches to when you approve its plan."
    case .panelSound: return "A macOS sound played when a panel appears."
    case .waitingNotices:
      return "A corner card when an agent has been waiting for you for a while."
    case .waitingNoticeDelay: return "How long after an agent stops the notice appears."
    case .waitingNoticeDuration:
      return "How long a notice stays up before it closes by itself."
    case .approvalCard: return "A corner card when an approval waits while you work."
    case .approvalCardDelay:
      return "How long an approval waits for a pause before its card shows."
    case .appearance: return "Light or dark for panels and Settings, or follow macOS."
    case .accentColor: return "The colour of Approve and highlights on panels and in Settings."
    case .editorApp: return "The app Open in Editor uses for config.json."
    case .contextCheckpointsEnabled:
      return "Nudge long Claude Code sessions toward a deliberate compaction."
    case .contextMode: return "Show a panel, or add the note silently."
    case .contextStandardThresholds: return "Soft, status and insist, in tokens."
    case .contextMillionThresholds: return "Soft, status and insist, in tokens."
    case .contextModelThresholds: return "A ladder for model IDs starting with a prefix."
    case .contextRearmBelow: return "A drop this far below the peak counts as a fresh start."
    case .contextHandoffFile: return "Where Claude writes a handoff, relative to the project."
    case .contextNoteSoft: return "Sent in silent mode at the first checkpoint."
    case .contextNoteStatus: return "Sent in silent mode at the second checkpoint."
    case .contextNoteInsist: return "Sent in silent mode at the third checkpoint."
    case .contextNoteCompact: return "Sent when you choose Compact after this step."
    case .contextNoteHandoff: return "Sent when you choose Hand off & start fresh."
    case .contextMenuBarMeter: return "List each live session's context in the menu."
    }
  }

  public var explanation: String {
    switch self {
    case .armDelay:
      return
        "How long a new panel ignores keys and clicks after it appears, so a keystroke meant for"
        + " whatever you were doing a moment ago can't accidentally answer it. Raise it if answers"
        + " land before you meant to make them; lower it if the panel feels slow to respond. Arm"
        + " delay after an answer uses its own, usually shorter, delay for a panel shown right"
        + " after you've just answered the one before it, since you're already looking at the"
        + " screen."
    case .chainedArmDelay:
      return
        "The same protection as arm delay, but for a panel that appears right after you've just"
        + " answered the previous one in the queue. It can be much shorter than arm delay, because"
        + " you're already looking at the panel rather than switching your attention to it from"
        + " somewhere else. Raise it if the next panel in a chain still catches a stray keystroke;"
        + " lower it, down to 0, if waiting between chained panels feels slow."
    case .idleSeconds:
      return
        "How long your keyboard, mouse and scrolling must have been quiet before a queued panel is"
        + " shown, counted from your last input rather than from when the request arrives — so if"
        + " you've already been away that long, the panel appears right away instead of waiting"
        + " again. Raise it if panels still appear while you're pausing mid-thought; lower it if"
        + " you want them to show up sooner. Grace period runs first and separately, giving a"
        + " request a chance to be answered in the chat before it even joins this queue."
    case .graceSeconds:
      return
        "How long a request waits, starting the moment it arrives, before joining the queue — it's"
        + " the one wait that always starts at arrival, rather than counting from your last input"
        + " the way wait for idle does. Set it above 0 if you often answer Claude Code in its own"
        + " chat and would rather skip the panel entirely when you do; leave it at 0 if you want a"
        + " panel every time. It only recognises chat answers from Claude Code, so for the other"
        + " agents it just adds a delay before the panel appears, on top of wait for idle."
    case .snoozeMinutes:
      return
        "The durations offered by the panel's Snooze menu and the menu-bar app's own Snooze"
        + " submenu, in the order they're listed. Set the presets to the lengths of quiet time you"
        + " actually use, from 1 to 6 values between 10 seconds and 24 hours, like 30s, 5, 15m, 1h"
        + " (a bare number is minutes). It's a single, top-level"
        + " list: snoozing isn't tied to one agent, so a per-agent override here has no effect on"
        + " the menu-bar app's own menu."
    case .quietHours:
      return
        "Windows that repeat every week, in which panels wait exactly as they do during a snooze:"
        + " requests go to their chats and can still be answered there. Each window names the"
        + " days it starts on and a start and end time; an end earlier than the start runs past"
        + " midnight into the next morning. Ending quiet time from the menu, Settings or"
        + " countersign snooze off also skips the window that is running now. It's a single,"
        + " top-level list, at most 7 windows, and applies to every agent."
    case .handoffApps:
      return
        "Bundle IDs of apps where you'd rather answer in that app's own chat than see a panel."
        + " When a panel is about to appear and the frontmost app is on this list, and it's also the"
        + " app the request came from, no panel appears at all; the request goes to the agent's own"
        + " prompt instead. It's checked at that moment, after wait for idle, rather than when the"
        + " request arrives, so switching to another app before then still gets you a panel, and"
        + " staying in the asking app means its own prompt comes only after that pause. Add an app"
        + " once you notice you always end up answering there anyway; a request from any other app"
        + " still gets a panel as normal."
    case .checkForUpdates:
      return
        "Lets the menu-bar app check once a day for a newer release of Countersign and let you"
        + " know. Turn it on if you'd like to hear about new versions without checking yourself; it"
        + " has no effect on approval panels either way. Choosing Check for Updates… in the menu"
        + " always checks immediately, whether this is on or off."
    case .questionNotes:
      return
        "Adds a \"+ Add a note\" link under a question panel's options, so you can type extra"
        + " context that's sent back with the option you pick. Turn it on if you often want to"
        + " explain your choice beyond picking one of the offered options; leave it off to keep"
        + " question panels to just their options. It only affects question panels, not the plain"
        + " approval or plan panels."
    case .quitBehavior:
      return
        "What choosing Quit Countersign in the menu-bar app does: ask each time, keep panels"
        + " appearing after it quits, or quit and pause panels until you open the app again. Change"
        + " it if you're tired of the quit question, or if you'd rather panels stop the moment you"
        + " quit rather than keep coming from your agents' hooks. Ticking Don't ask again in that"
        + " question writes your choice here directly, so this is also where you'd come to make it"
        + " ask again."
    case .modeAfterPlan:
      return
        "The permission mode Claude Code continues in once you approve a plan on the plan panel."
        + " Ask before edits keeps asking before each change, Accept edits lets it edit files"
        + " without asking, and Auto hands the decisions to Claude Code's auto mode. The plan"
        + " panel's \"then:\" menu starts on this choice, and you can still pick another there"
        + " for a single plan. Only Claude Code sends plans, so the other agents are unaffected."
    case .panelSound:
      return
        "A system sound played once when an approval panel, a context checkpoint or a test panel"
        + " appears. It stays silent for the next panel in a chain you are already answering,"
        + " after the result card, and for notices. None, the default, plays nothing; the play"
        + " button next to the menu lets you hear a sound before you pick it."
    case .waitingNotices:
      return
        "When an agent finishes a turn and waits for you, Countersign shows a corner card, \"Claude"
        + " Code is waiting for you\" with the project's name, once it has waited for the time"
        + " below. It is on by default, and setup adds the Stop hook next to the permission hook."
        + " Turning it off removes the Stop hook again, after showing you the change, so it is"
        + " changed here and not by editing config.json. It is top-level only."
    case .waitingNoticeDelay:
      return
        "How long an agent has been waiting before the notice appears, from 10 seconds to 1 hour."
        + " Type a number of seconds or a value with a unit, like \"90s\" or \"2m\". It has no"
        + " effect while Waiting-agent notices is off. One agent can have its own value under"
        + " hosts in config.json."
    case .waitingNoticeDuration:
      return
        "How long a waiting-agent notice stays on screen before it closes by itself, from 3"
        + " seconds to 1 hour. Only the time it is visible counts: while a panel or quiet time"
        + " hides it, or while the pointer rests on it, the clock stops. Approval cards stay"
        + " until you answer."
    case .approvalCard:
      return
        "While you keep typing or moving the mouse, a panel waits for a pause, and some agents just"
        + " stop with no prompt of their own. The approval card tells you in a corner without"
        + " taking your keys, and Show brings the panel up at once. Pick the agents that show it:"
        + " Claude Code is off by default because its request also waits in the chat."
    case .approvalCardDelay:
      return
        "How long a request waits for a pause in your typing before its approval card appears."
        + " Shorter tells you sooner; longer leaves room for a natural pause, which shows the"
        + " panel with no card at all."
    case .appearance:
      return
        "Whether approval panels and this Settings window are light or dark. System follows the"
        + " appearance chosen in macOS and switches when it does; Light and Dark keep them that way"
        + " whatever macOS uses. Choose one if you'd like panels to stand out from the rest of your"
        + " screen, or to match an app that doesn't follow macOS. It changes nothing outside"
        + " Countersign, and the menu-bar icon follows the menu bar as before."
    case .accentColor:
      return
        "The colour of Approve and the other filled buttons, and of highlights such as a selected"
        + " option and the arm lock's progress line, on every panel and in this Settings window."
        + " Pick a preset, or any colour with the colour well after them. Text drawn in the colour"
        + " is darkened in light appearance, or lightened in dark, until it's easy to read, and a"
        + " filled button's label is near-black or white, whichever reads better on it. Deny stays"
        + " red, the mark in a panel's header keeps the app icon's amber, and the menu-bar icon"
        + " stays monochrome."
    case .editorApp:
      return
        "Which app \"Open in Editor\" opens config.json with, both here and next to an agent's"
        + " own values. While it's on \"Ask every time\", Open in Editor asks which app to use"
        + " until you pick one with \"Always use this app\"; you can also pick one here from the"
        + " menu, and \"Other…\" if that editor isn't offered."
    case .contextCheckpointsEnabled:
      return
        "Watches how large each Claude Code session's context has grown and steers Claude toward"
        + " a deliberate compaction at a natural breakpoint, instead of letting auto-compact"
        + " interrupt a task. It reads the session's transcript, so a reading can lag a turn"
        + " behind. Countersign only steers Claude; it cannot run /compact itself."
    case .contextMode:
      return
        "Panel shows a checkpoint panel where you choose what happens next; Silent skips the"
        + " panel and adds the matching note to Claude's next prompt instead. Pick Silent if you"
        + " would rather not be interrupted. The panel steers Claude in the same way, and cannot"
        + " run /compact itself."
    case .contextStandardThresholds:
      return
        "The context sizes, in tokens, at which the soft, status and insist checkpoints fire for"
        + " a session on the 200K window, lowest first. A session is counted as 1M only when its"
        + " model ID carries the [1m] tag, so anything else uses this ladder. A ladder for one"
        + " model beats both window ladders."
    case .contextMillionThresholds:
      return
        "The context sizes, in tokens, at which the soft, status and insist checkpoints fire for"
        + " a session on the 1M window, lowest first. Countersign tells 1M from 200K by the [1m]"
        + " tag in the model ID. A ladder for one model beats both window ladders."
    case .contextModelThresholds:
      return
        "A checkpoint ladder for every model whose ID starts with a prefix you give, such as"
        + " claude-opus-5. It wins over both the 200K and the 1M ladders for those models. Use it"
        + " when one model needs earlier or later checkpoints than the rest; remove it to fall"
        + " back to the window ladders."
    case .contextRearmBelow:
      return
        "After compaction or a fresh start, a session's context falls well below where it was."
        + " When the reading drops to this fraction of the highest one seen, the checkpoints"
        + " start over and can fire again. Raise it to re-arm sooner; lower it to require a"
        + " bigger drop."
    case .contextHandoffFile:
      return
        "The file, relative to the project, that Claude is asked to write when you hand off and"
        + " start fresh, and that the insist note names. {handoffFile} in a note is filled in"
        + " with it. Change it if your projects keep handoffs somewhere else."
    case .contextNoteSoft:
      return
        "The text added to Claude's prompt in silent mode when the first checkpoint is reached."
        + " {tokens} is filled in with the session's current context size and {handoffFile} with"
        + " the handoff file. Reset it to get the built-in wording back."
    case .contextNoteStatus:
      return
        "The text added to Claude's prompt in silent mode when the second checkpoint is"
        + " reached. {tokens} is filled in with the session's current context size and"
        + " {handoffFile} with the handoff file. Reset it to get the built-in wording back."
    case .contextNoteInsist:
      return
        "The text added to Claude's prompt in silent mode when the third checkpoint is reached,"
        + " asking Claude to stop after the current step. {tokens} is filled in with the"
        + " session's current context size and {handoffFile} with the handoff file. Reset it to"
        + " get the built-in wording back."
    case .contextNoteCompact:
      return
        "The text sent to Claude when you choose Compact after this step on a checkpoint panel."
        + " {tokens} is filled in with the session's current context size and {handoffFile} with"
        + " the handoff file. Reset it to get the built-in wording back."
    case .contextNoteHandoff:
      return
        "The text sent to Claude when you choose Hand off & start fresh on a checkpoint panel."
        + " {tokens} is filled in with the session's current context size and {handoffFile} with"
        + " the handoff file. Reset it to get the built-in wording back."
    case .contextMenuBarMeter:
      return
        "Adds each live Claude Code session's context size to the menu-bar menu, so you can see"
        + " which one is growing. The meter reads each session's transcript when the menu opens,"
        + " so a reading can lag a turn behind, and it costs nothing while the menu is closed."
    }
  }

  public var defaultText: String {
    switch self {
    case .armDelay: return Self.secondsText(Settings.defaultArmDelay)
    case .chainedArmDelay: return Self.secondsText(Settings.defaultChainedArmDelay)
    case .idleSeconds: return Self.secondsText(Settings.defaultIdleSeconds)
    case .graceSeconds: return Self.secondsText(Settings.defaultGraceSeconds)
    case .snoozeMinutes: return PreferenceRules.snoozeListText(Settings.defaultSnoozePresets)
    case .quietHours: return "No windows"
    case .handoffApps: return Self.handoffAppsText(Settings.defaultHandoffApps)
    case .checkForUpdates: return Self.boolText(Settings.defaultCheckForUpdates)
    case .questionNotes: return Self.boolText(Settings.defaultQuestionNotes)
    case .quitBehavior: return Settings.defaultQuitBehavior.title
    case .modeAfterPlan: return Settings.defaultModeAfterPlan.title
    case .panelSound: return PanelSound.title(Settings.defaultPanelSound)
    case .waitingNotices: return Self.boolText(Settings.defaultWaitingNotices)
    case .waitingNoticeDelay:
      return DurationText.describe(Settings.defaultWaitingNoticeDelay)
    case .waitingNoticeDuration:
      return DurationText.describe(Settings.defaultWaitingNoticeDuration)
    case .approvalCard:
      return Self.agentListText(Host.allCases.filter { Settings.defaultApprovalCard(for: $0) })
    case .approvalCardDelay: return Self.secondsText(Settings.defaultApprovalCardDelay)
    case .appearance: return Settings.defaultAppearance.title
    case .accentColor: return AccentPreset.name(of: Settings.defaultAccentColor)
    case .editorApp: return "Ask every time"
    case .contextCheckpointsEnabled: return Self.boolText(ContextCheckpointSettings.defaultEnabled)
    case .contextMode: return ContextCheckpointSettings.defaultMode.rawValue.capitalized
    case .contextStandardThresholds:
      return PreferenceReset.ladderText(ContextCheckpointSettings.defaultStandardThresholds)
    case .contextMillionThresholds:
      return PreferenceReset.ladderText(ContextCheckpointSettings.defaultMillionThresholds)
    case .contextModelThresholds: return "No models"
    case .contextRearmBelow:
      return PreferenceReset.percentText(ContextCheckpointSettings.defaultRearmBelow)
    case .contextHandoffFile: return ContextCheckpointSettings.defaultHandoffFile
    case .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteCompact,
      .contextNoteHandoff:
      return "Built-in wording"
    case .contextMenuBarMeter: return Self.boolText(ContextCheckpointSettings.default.menuBarMeter)
    }
  }

  static func agentListText(_ hosts: [Host]) -> String {
    let names = hosts.map(\.displayName)
    guard let last = names.last else { return "No agents" }
    guard names.count > 1 else { return last }
    return "\(names.dropLast().joined(separator: ", ")) and \(last)"
  }

  static func secondsText(_ value: Double) -> String {
    "\(PreferenceRules.numberText(value)) second\(value == 1 ? "" : "s")"
  }

  private static func handoffAppsText(_ apps: [String]) -> String {
    apps.isEmpty ? "No apps" : apps.joined(separator: ", ")
  }

  private static func boolText(_ value: Bool) -> String {
    value ? "On" : "Off"
  }
}
