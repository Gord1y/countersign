import Foundation

public struct ContextCheckpointInput: Sendable, Equatable {
  public var sessionID: String
  public var cwd: String
  public var transcriptPath: String?
  public var permissionMode: String?
  public var agentID: String?

  public init(
    sessionID: String, cwd: String, transcriptPath: String?, permissionMode: String?,
    agentID: String? = nil
  ) {
    self.sessionID = sessionID
    self.cwd = cwd
    self.transcriptPath = transcriptPath
    self.permissionMode = permissionMode
    self.agentID = agentID
  }
}

public struct ContextCheckpointPrompt: Sendable, Equatable {
  public var tokens: Int
  public var level: ContextLevel
  public var ladder: [Int]
  public var modelID: String?
  public var handoffFile: String
  public var notes: ContextCheckpointNotes
  public var choices: [ContextCheckpointChoice]
  public var compactions: Int
  public var maxCompactions: Int

  public init(
    tokens: Int, level: ContextLevel, ladder: [Int], modelID: String?, handoffFile: String,
    notes: ContextCheckpointNotes, choices: [ContextCheckpointChoice],
    compactions: Int = 0, maxCompactions: Int = ContextCheckpointSettings.defaultMaxCompactions
  ) {
    self.tokens = tokens
    self.level = level
    self.ladder = ladder
    self.modelID = modelID
    self.handoffFile = handoffFile
    self.notes = notes
    self.choices = choices
    self.compactions = compactions
    self.maxCompactions = maxCompactions
  }
}

public enum ContextCheckpointChoice: String, Sendable, Equatable, CaseIterable {
  case continueWorking, compactAfterStep, handOff, notThisSession

  public var title: String {
    switch self {
    case .continueWorking: return "Continue"
    case .compactAfterStep: return "Compact after this step"
    case .handOff: return "Hand off & start fresh"
    case .notThisSession: return "Not this session"
    }
  }

  public var listText: String {
    switch self {
    case .compactAfterStep: return "Compact"
    case .handOff: return "Hand off"
    case .continueWorking: return "Continue"
    case .notThisSession: return "Not this session"
    }
  }

  public var configName: String {
    switch self {
    case .compactAfterStep: return "compact"
    case .handOff: return "handoff"
    case .continueWorking: return "continue"
    case .notThisSession: return "mute"
    }
  }

  public init?(configName: String) {
    guard let choice = Self.allCases.first(where: { $0.configName == configName }) else {
      return nil
    }
    self = choice
  }

  public func outcome(for prompt: ContextCheckpointPrompt) -> ApprovalOutcome {
    switch self {
    case .continueWorking, .notThisSession:
      return .noDecision
    case .compactAfterStep:
      return .addContext(
        ContextCheckpointNotes.render(
          prompt.notes.compact, tokens: prompt.tokens, handoffFile: prompt.handoffFile,
          compactions: prompt.compactions))
    case .handOff:
      return .addContext(
        ContextCheckpointNotes.render(
          prompt.notes.handoff, tokens: prompt.tokens, handoffFile: prompt.handoffFile,
          compactions: prompt.compactions))
    }
  }
}

public enum ContextCheckpointDecision: Sendable, Equatable {
  case nothing
  case inject(String)
  case panel(ContextCheckpointPrompt)
}

public struct ContextCheckpointPlan: Sendable, Equatable {
  public var state: ContextCheckpointState
  public var decision: ContextCheckpointDecision

  public init(state: ContextCheckpointState, decision: ContextCheckpointDecision) {
    self.state = state
    self.decision = decision
  }
}

public enum ContextCheckpointPlanner {
  public static func plan(
    reading: ContextReading, previous: ContextCheckpointState, settings: ContextCheckpointSettings,
    transcriptPath: String?, project: String, now: Date,
    levels: [ContextLevel] = ContextLevel.allCases
  ) -> ContextCheckpointPlan {
    let ladderSettings = ContextLadderSettings(settings)
    let step = ContextLadder.step(
      tokens: reading.tokens, modelID: reading.modelID,
      hasMillionTokenWindow: reading.hasMillionTokenWindow, compactionID: reading.compactionID,
      previous: previous, settings: ladderSettings, levels: levels)

    var state = step.state
    state.hasMillionTokenWindow = reading.hasMillionTokenWindow
    state.transcriptPath = transcriptPath
    state.project = project
    state.updatedAt = now

    guard let level = step.fire else {
      return ContextCheckpointPlan(state: state, decision: .nothing)
    }

    switch (settings.mode, level) {
    case (.silent, _), (.panel, .stop):
      let pastCompactionLimit = state.compactions >= settings.maxCompactions && level != .stop
      let chosenTemplate =
        pastCompactionLimit ? settings.notes.limit : template(for: level, in: settings.notes)
      let note = ContextCheckpointNotes.render(
        chosenTemplate, tokens: reading.tokens, handoffFile: settings.handoffFile,
        compactions: state.compactions)
      return ContextCheckpointPlan(state: state, decision: .inject(note))
    case (.panel, _):
      let ladder = ContextLadder.thresholds(
        modelID: state.modelID, hasMillionTokenWindow: reading.hasMillionTokenWindow,
        settings: ladderSettings)
      let prompt = ContextCheckpointPrompt(
        tokens: reading.tokens, level: level, ladder: ladder, modelID: state.modelID,
        handoffFile: settings.handoffFile, notes: settings.notes,
        choices: settings.choices.offered(
          at: level, compactions: state.compactions, maxCompactions: settings.maxCompactions),
        compactions: state.compactions, maxCompactions: settings.maxCompactions)
      return ContextCheckpointPlan(state: state, decision: .panel(prompt))
    }
  }

  private static func template(for level: ContextLevel, in notes: ContextCheckpointNotes)
    -> String
  {
    switch level {
    case .soft: return notes.soft
    case .status: return notes.status
    case .insist: return notes.insist
    case .stop: return notes.stop
    }
  }
}
