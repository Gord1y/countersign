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

  public static let names: [String] = ["soft", "status", "insist", "stop", "compact", "handoff"]
  public static let maximumLength = 4000

  public static let `default` = ContextCheckpointNotes(
    soft:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens. The user prefers to compact at a natural breakpoint rather than let auto-compact interrupt a task. If you have just finished a logical piece of work, pause, suggest /compact, and say in one line what state must survive it. Otherwise carry on; this note needs no reply.",
    status:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens. The user would like a short status before it grows further: when the current step is done, say what is finished, what remains and roughly how much. If what remains is small, say so and carry on without compacting; otherwise recommend /compact and list what its summary must preserve.",
    insist:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, which the user considers too large to keep working well. The user prefers that you stop after the current step, write or update {handoffFile} with the current state, the decisions made, the remaining steps and any gotchas, and then ask them to choose between /compact and /clear followed by that file. The user prefers no new sub-tasks until they decide.",
    stop:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, the point where the user wants work to stop and continue in a fresh session while the prompt cache is still warm. Do not start any new step, tool call or subagent beyond what this note asks. If subagents are still running, first collect what each has found and where it stands, by waiting for its result or asking it for its state, then stop it. Then write {handoffFile}: the goal, the current state including each subagent's results and unfinished work, the decisions made and why, the remaining steps and any gotchas, so a new session can continue from that file alone. Then stop and tell the user it is ready for /clear. Do not suggest /compact: once the cache has expired, compacting a session this large costs more than starting fresh from the handoff.",
    compact:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, and the user chose to compact after the current step. Finish the step you are on without starting new work, then stop and list, in a few lines, what the /compact summary must preserve, so the user can run /compact.",
    handoff:
      "Context note from Countersign, the user's approval app: this session's context is about {tokens} tokens, and the user chose to hand off and start fresh. Finish or safely pause the current step, then write {handoffFile}: the goal, the current state, the decisions made and why, the remaining steps and any gotchas, so a new session can continue from that file alone. Then stop and tell the user it is ready for /clear."
  )

  public init(
    soft: String, status: String, insist: String, stop: String, compact: String, handoff: String
  ) {
    self.soft = soft
    self.status = status
    self.insist = insist
    self.stop = stop
    self.compact = compact
    self.handoff = handoff
  }

  public static func render(_ template: String, tokens: Int, handoffFile: String) -> String {
    template
      .replacingOccurrences(of: "{tokens}", with: tokenText(tokens))
      .replacingOccurrences(of: "{handoffFile}", with: handoffFile)
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
  public var handoffFile: String
  public var notes: ContextCheckpointNotes
  public var menuBarMeter: Bool
  public var coldCacheCard: Bool

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
      handoffFile: hostValues?.handoffFile ?? top?.handoffFile ?? defaultHandoffFile,
      notes: ContextCheckpointNotes(
        soft: note("soft"), status: note("status"), insist: note("insist"),
        stop: note("stop"), compact: note("compact"), handoff: note("handoff")),
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

    return ContextCheckpointSettings(
      enabled: hostValues?.enabled ?? top?.enabled ?? defaultEnabled,
      mode: hostValues?.mode ?? top?.mode ?? defaultMode,
      standardThresholds: hostValues?.standardThresholds ?? top?.standardThresholds
        ?? defaultStandardThresholds,
      millionThresholds: hostValues?.millionThresholds ?? top?.millionThresholds
        ?? defaultMillionThresholds,
      modelThresholds: hostValues?.modelThresholds ?? top?.modelThresholds ?? [:],
      rearmBelow: hostValues?.rearmBelow ?? top?.rearmBelow ?? defaultRearmBelow,
      handoffFile: hostValues?.handoffFile ?? top?.handoffFile ?? defaultHandoffFile,
      notes: ContextCheckpointNotes(
        soft: note("soft"), status: note("status"), insist: note("insist"),
        stop: note("stop"), compact: note("compact"), handoff: note("handoff")),
      menuBarMeter: hostValues?.menuBarMeter ?? top?.menuBarMeter ?? false,
      coldCacheCard: hostValues?.coldCacheCard ?? top?.coldCacheCard ?? true)
  }
}
