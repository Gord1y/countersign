import Foundation

public enum ContextCheckpointMode: String, Sendable, Equatable, CaseIterable {
  case panel
  case silent
}

public struct ContextCheckpointNotes: Sendable, Equatable {
  public var soft: String
  public var status: String
  public var insist: String
  public var stop: String
  public var compact: String
  public var handoff: String
  public var limit: String

  public static let names: [String] = [
    "soft", "status", "insist", "stop", "compact", "handoff", "limit",
  ]
  public static let maximumLength = 4000

  public static let `default` = ContextCheckpointNotes(
    soft:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens. The user prefers to compact at a natural breakpoint rather than let auto-compact interrupt a task. If you have just finished a logical piece of work, pause, suggest /compact, and say in one line what state must survive it. Otherwise carry on; this note needs no reply.",
    status:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens. When the current step is done, stop and ask the user whether to compact or to hand off to a fresh session, and say in one line what either would have to keep. Start no new sub-task until they choose.",
    insist:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, which the user considers too large to keep working well. Stop after the current step and start no new sub-task. Write a handoff the way this project's instructions say to hand off, or to {handoffFile} if they name no way, with the current state, the decisions made, the remaining steps and any gotchas, then ask the user to choose between /compact and /clear followed by that handoff.",
    stop:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, the point where the user wants this session to end and the work to continue in a fresh one while the prompt cache is still warm. Finish the task in hand, but start no new step, unit or subagent: let running subagents and the current step finish, and keep what they produce. Leave everything that is not finished exactly as it is: keep worktrees, branches, uncommitted changes and run or plan folders, and clean nothing up. Then write a handoff the way this project's instructions say to hand off, or to {handoffFile} if they name no way: the goal, the current state with each subagent's results and where each unfinished piece lives, the decisions made and why, the remaining steps and any gotchas, so a new session can continue from it alone without researching again. Then stop and tell the user it is ready for /clear. Do not suggest /compact: compacting a session this large costs more than starting fresh from the handoff.",
    compact:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, and the user chose to compact after the current step. Finish the step you are on without starting new work, then stop and list, in a few lines, what the /compact summary must preserve, so the user can run /compact.",
    handoff:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, and the user chose to hand off and start fresh. Finish or safely pause the current step without starting new work, and clean nothing up: keep worktrees, branches, uncommitted changes and run or plan folders as they are. Then write a handoff the way this project's instructions say to hand off, or to {handoffFile} if they name no way: the goal, the current state and where each unfinished piece lives, the decisions made and why, the remaining steps and any gotchas, so a new session can continue from it alone. Then stop and tell the user it is ready for /clear.",
    limit:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens and it has been compacted {compactions} times, as many as the user allows before a summary keeps too little detail. When the current step is done, start no new work and clean nothing up: keep worktrees, branches, uncommitted changes and run or plan folders as they are. Write a handoff the way this project's instructions say to hand off, or to {handoffFile} if they name no way, with the goal, the current state and where each unfinished piece lives, the decisions made and why, the remaining steps and any gotchas, then stop and tell the user it is ready for /clear."
  )

  public init(
    soft: String, status: String, insist: String, stop: String, compact: String, handoff: String,
    limit: String
  ) {
    self.soft = soft
    self.status = status
    self.insist = insist
    self.stop = stop
    self.compact = compact
    self.handoff = handoff
    self.limit = limit
  }

  public static func render(
    _ template: String, tokens: Int, handoffFile: String, compactions: Int
  ) -> String {
    template
      .replacingOccurrences(of: "{tokens}", with: tokenText(tokens))
      .replacingOccurrences(of: "{handoffFile}", with: handoffFile)
      .replacingOccurrences(of: "{compactions}", with: String(compactions))
  }

  public static func tokenText(_ tokens: Int) -> String {
    let nonNegative = max(tokens, 0)
    if nonNegative < 999_500 {
      return "\((nonNegative + 500) / 1000)K"
    }
    let tenths = (nonNegative + 50_000) / 100_000
    return "\(tenths / 10).\(tenths % 10)M"
  }

  func text(named name: String) -> String? {
    switch name {
    case "soft": return soft
    case "status": return status
    case "insist": return insist
    case "stop": return stop
    case "compact": return compact
    case "handoff": return handoff
    case "limit": return limit
    default: return nil
    }
  }
}

public struct ContextCheckpointFileValues: Sendable, Equatable {
  public var enabled: Bool?
  public var mode: ContextCheckpointMode?
  public var standardThresholds: [Int]?
  public var millionThresholds: [Int]?
  public var modelThresholds: [String: [Int]]?
  public var rearmBelow: Double?
  public var maxCompactions: Int?
  public var choices: [String: [ContextCheckpointChoice]]
  public var handoffFile: String?
  public var notes: [String: String]
  public var menuBarMeter: Bool?
  public var coldCacheCard: Bool?

  public init(
    enabled: Bool? = nil,
    mode: ContextCheckpointMode? = nil,
    standardThresholds: [Int]? = nil,
    millionThresholds: [Int]? = nil,
    modelThresholds: [String: [Int]]? = nil,
    rearmBelow: Double? = nil,
    maxCompactions: Int? = nil,
    choices: [String: [ContextCheckpointChoice]] = [:],
    handoffFile: String? = nil,
    notes: [String: String] = [:],
    menuBarMeter: Bool? = nil,
    coldCacheCard: Bool? = nil
  ) {
    self.enabled = enabled
    self.mode = mode
    self.standardThresholds = standardThresholds
    self.millionThresholds = millionThresholds
    self.modelThresholds = modelThresholds
    self.rearmBelow = rearmBelow
    self.maxCompactions = maxCompactions
    self.choices = choices
    self.handoffFile = handoffFile
    self.notes = notes
    self.menuBarMeter = menuBarMeter
    self.coldCacheCard = coldCacheCard
  }
}

public struct ContextCheckpointSettings: Sendable, Equatable {
  public var enabled: Bool
  public var mode: ContextCheckpointMode
  public var standardThresholds: [Int]
  public var millionThresholds: [Int]
  public var modelThresholds: [String: [Int]]
  public var rearmBelow: Double
  public var maxCompactions: Int
  public var choices: ContextCheckpointChoices
  public var handoffFile: String
  public var notes: ContextCheckpointNotes
  public var menuBarMeter: Bool
  public var coldCacheCard: Bool

  public static let defaultMaxCompactions = 5
  public static let maxCompactionsRange: ClosedRange<Int> = 0...50
  public static let defaultStandardThresholds: [Int] = [100_000, 130_000, 160_000]
  public static let defaultMillionThresholds: [Int] = [200_000, 300_000, 500_000]
  public static let rearmBelowRange: ClosedRange<Double> = 0.1...0.95
  public static let defaultRearmBelow: Double = 0.6
  public static let defaultHandoffFile = "notes/handoff.md"
  public static let defaultMode = ContextCheckpointMode.panel
  public static let defaultEnabled = true

  public static let `default` = ContextCheckpointSettings(
    enabled: defaultEnabled,
    mode: defaultMode,
    standardThresholds: defaultStandardThresholds,
    millionThresholds: defaultMillionThresholds,
    modelThresholds: [:],
    rearmBelow: defaultRearmBelow,
    maxCompactions: defaultMaxCompactions,
    choices: .default,
    handoffFile: defaultHandoffFile,
    notes: .default,
    menuBarMeter: false,
    coldCacheCard: true)

  public init(
    enabled: Bool,
    mode: ContextCheckpointMode,
    standardThresholds: [Int],
    millionThresholds: [Int],
    modelThresholds: [String: [Int]],
    rearmBelow: Double,
    maxCompactions: Int,
    choices: ContextCheckpointChoices,
    handoffFile: String,
    notes: ContextCheckpointNotes,
    menuBarMeter: Bool,
    coldCacheCard: Bool
  ) {
    self.enabled = enabled
    self.mode = mode
    self.standardThresholds = standardThresholds
    self.millionThresholds = millionThresholds
    self.modelThresholds = modelThresholds
    self.rearmBelow = rearmBelow
    self.maxCompactions = maxCompactions
    self.choices = choices
    self.handoffFile = handoffFile
    self.notes = notes
    self.menuBarMeter = menuBarMeter
    self.coldCacheCard = coldCacheCard
  }

  public func forCodex(windowTokens: Int) -> ContextCheckpointSettings {
    var settings = self
    settings.mode = .silent
    settings.standardThresholds = ContextLadder.codexThresholds(windowTokens: windowTokens)
    settings.millionThresholds = settings.standardThresholds
    settings.modelThresholds = [:]
    return settings
  }

  private static func resolveCodex(
    top: ContextCheckpointFileValues?, host hostValues: ContextCheckpointFileValues?
  ) -> ContextCheckpointSettings {
    func note(_ name: String) -> String {
      hostValues?.notes[name] ?? top?.notes[name]
        ?? ContextCheckpointNotes.default.text(named: name) ?? ""
    }

    return ContextCheckpointSettings(
      enabled: hostValues?.enabled ?? top?.enabled ?? defaultEnabled,
      mode: .silent,
      standardThresholds: defaultStandardThresholds,
      millionThresholds: defaultMillionThresholds,
      modelThresholds: [:],
      rearmBelow: hostValues?.rearmBelow ?? top?.rearmBelow ?? defaultRearmBelow,
      maxCompactions: defaultMaxCompactions,
      choices: .default,
      handoffFile: hostValues?.handoffFile ?? top?.handoffFile ?? defaultHandoffFile,
      notes: ContextCheckpointNotes(
        soft: note("soft"), status: note("status"), insist: note("insist"),
        stop: note("stop"), compact: note("compact"), handoff: note("handoff"),
        limit: note("limit")),
      menuBarMeter: false,
      coldCacheCard: false)
  }

  public static var off: ContextCheckpointSettings {
    var settings = ContextCheckpointSettings.default
    settings.enabled = false
    return settings
  }

  public static func resolve(
    top: ContextCheckpointFileValues?, host hostValues: ContextCheckpointFileValues?,
    for host: Host
  ) -> ContextCheckpointSettings {
    switch host {
    case .claude: break
    case .codex: return resolveCodex(top: top, host: hostValues)
    case .cursor, .antigravity: return .off
    }

    func note(_ name: String) -> String {
      hostValues?.notes[name] ?? top?.notes[name]
        ?? ContextCheckpointNotes.default.text(named: name) ?? ""
    }

    func choices(_ name: String) -> [ContextCheckpointChoice] {
      hostValues?.choices[name] ?? top?.choices[name]
        ?? ContextCheckpointChoices.default.list(named: name) ?? []
    }

    return ContextCheckpointSettings(
      enabled: hostValues?.enabled ?? top?.enabled ?? defaultEnabled,
      mode: hostValues?.mode ?? top?.mode ?? defaultMode,
      standardThresholds: hostValues?.standardThresholds ?? top?.standardThresholds
        ?? defaultStandardThresholds,
      millionThresholds: hostValues?.millionThresholds ?? top?.millionThresholds
        ?? defaultMillionThresholds,
      modelThresholds: hostValues?.modelThresholds ?? top?.modelThresholds ?? [:],
      rearmBelow: hostValues?.rearmBelow ?? top?.rearmBelow ?? defaultRearmBelow,
      maxCompactions: hostValues?.maxCompactions ?? top?.maxCompactions ?? defaultMaxCompactions,
      choices: ContextCheckpointChoices(
        soft: choices("soft"), status: choices("status"), insist: choices("insist")),
      handoffFile: hostValues?.handoffFile ?? top?.handoffFile ?? defaultHandoffFile,
      notes: ContextCheckpointNotes(
        soft: note("soft"), status: note("status"), insist: note("insist"),
        stop: note("stop"), compact: note("compact"), handoff: note("handoff"),
        limit: note("limit")),
      menuBarMeter: hostValues?.menuBarMeter ?? top?.menuBarMeter ?? false,
      coldCacheCard: hostValues?.coldCacheCard ?? top?.coldCacheCard ?? true)
  }
}
