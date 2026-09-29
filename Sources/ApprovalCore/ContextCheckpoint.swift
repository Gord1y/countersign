import Foundation

public struct ContextCheckpointInput: Sendable, Equatable {
  public var sessionID: String
  public var cwd: String
  public var transcriptPath: String?
  public var permissionMode: String?

  public init(sessionID: String, cwd: String, transcriptPath: String?, permissionMode: String?) {
    self.sessionID = sessionID
    self.cwd = cwd
    self.transcriptPath = transcriptPath
    self.permissionMode = permissionMode
  }
}

public struct ContextCheckpointPrompt: Sendable, Equatable {
  public var tokens: Int
  public var level: ContextLevel
  public var ladder: [Int]
  public var modelID: String?
  public var handoffFile: String
  public var notes: ContextCheckpointNotes

  public init(
    tokens: Int, level: ContextLevel, ladder: [Int], modelID: String?, handoffFile: String,
    notes: ContextCheckpointNotes
  ) {
    self.tokens = tokens
    self.level = level
    self.ladder = ladder
    self.modelID = modelID
    self.handoffFile = handoffFile
    self.notes = notes
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

  public func outcome(for prompt: ContextCheckpointPrompt) -> ApprovalOutcome {
    switch self {
    case .continueWorking, .notThisSession:
      return .noDecision
    case .compactAfterStep:
      return .addContext(
        ContextCheckpointNotes.render(
          prompt.notes.compact, tokens: prompt.tokens, handoffFile: prompt.handoffFile))
    case .handOff:
      return .addContext(
        ContextCheckpointNotes.render(
          prompt.notes.handoff, tokens: prompt.tokens, handoffFile: prompt.handoffFile))
    }
  }

  public static func highlighted(for level: ContextLevel) -> ContextCheckpointChoice {
    switch level {
    case .soft, .status: return .compactAfterStep
    case .insist: return .handOff
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
    transcriptPath: String?, project: String, now: Date
  ) -> ContextCheckpointPlan {
    let ladderSettings = ContextLadderSettings(settings)
    let step = ContextLadder.step(
      tokens: reading.tokens, modelID: reading.modelID,
      hasMillionTokenWindow: reading.hasMillionTokenWindow, compactionID: reading.compactionID,
      previous: previous, settings: ladderSettings)

    var state = step.state
    state.transcriptPath = transcriptPath
    state.project = project
    state.updatedAt = now

    guard let level = step.fire else {
      return ContextCheckpointPlan(state: state, decision: .nothing)
    }

    switch settings.mode {
    case .silent:
      let note = ContextCheckpointNotes.render(
        template(for: level, in: settings.notes), tokens: reading.tokens,
        handoffFile: settings.handoffFile)
      return ContextCheckpointPlan(state: state, decision: .inject(note))
    case .panel:
      let ladder = ContextLadder.thresholds(
        modelID: state.modelID, hasMillionTokenWindow: reading.hasMillionTokenWindow,
        settings: ladderSettings)
      let prompt = ContextCheckpointPrompt(
        tokens: reading.tokens, level: level, ladder: ladder, modelID: state.modelID,
        handoffFile: settings.handoffFile, notes: settings.notes)
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
    }
  }
}
