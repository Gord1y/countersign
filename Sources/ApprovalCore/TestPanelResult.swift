import Foundation

public enum TestPanelResult {
  public static let closing = "Nothing reached an agent."

  public static func describe(
    _ outcome: ApprovalOutcome, kind: TestPanelKind, checkpointChoice: ContextCheckpointChoice?
  ) -> (title: String, detail: String) {
    let (title, effect) = titleAndEffect(outcome, kind: kind, checkpointChoice: checkpointChoice)
    return (title, "\(effect) \(closing)")
  }

  private static func titleAndEffect(
    _ outcome: ApprovalOutcome, kind: TestPanelKind, checkpointChoice: ContextCheckpointChoice?
  ) -> (String, String) {
    switch kind {
    case .command: return command(outcome)
    case .question: return question(outcome)
    case .plan: return plan(outcome)
    case .context: return context(outcome, choice: checkpointChoice)
    }
  }

  private static func command(_ outcome: ApprovalOutcome) -> (String, String) {
    switch outcome {
    case .allow(_, let updatedPermissions):
      if updatedPermissions.isEmpty {
        return ("Approved", "Claude Code would run the command.")
      }
      return (
        "Approved with a suggestion",
        "Claude Code would run the command and apply the rule you picked, so it stops asking for it."
      )
    case .deny(_, let interrupt):
      if interrupt {
        return (
          "Denied and stopped",
          "Claude Code would block the command and interrupt the turn instead of carrying on."
        )
      }
      return ("Denied", "Claude Code would block the command and tell Claude why.")
    case .noDecision:
      return ("Answered in chat", "Claude Code would show its own prompt for the command.")
    case .addContext:
      return unexpected
    }
  }

  private static func question(_ outcome: ApprovalOutcome) -> (String, String) {
    switch outcome {
    case .allow:
      return ("Submitted", "Your answers would go back to Claude as the answers to its question.")
    case .noDecision:
      return ("Answered in chat", "Claude Code would show its own question prompt.")
    case .deny, .addContext:
      return unexpected
    }
  }

  private static func plan(_ outcome: ApprovalOutcome) -> (String, String) {
    switch outcome {
    case .allow:
      return (
        "Approved",
        "Claude Code would treat the plan as approved and carry on in the mode you picked."
      )
    case .deny:
      return (
        "Kept planning",
        "Claude would be told the plan is not approved yet, with your feedback if you wrote any, and keep planning."
      )
    case .noDecision:
      return ("Answered in chat", "Claude Code would show its own plan prompt.")
    case .addContext:
      return unexpected
    }
  }

  private static func context(_ outcome: ApprovalOutcome, choice: ContextCheckpointChoice?) -> (
    String, String
  ) {
    switch outcome {
    case .addContext(let note):
      let title = choice?.title ?? "Sent a context note"
      return (title, "Claude would receive this note at its next request: \"\(note)\"")
    case .noDecision:
      if choice == .notThisSession {
        return (
          "Not this session",
          "Countersign would send nothing and mute this session: no further checkpoint until it ends."
        )
      }
      return ("Continued", "Countersign would send nothing and Claude would carry on.")
    case .allow, .deny:
      return unexpected
    }
  }

  private static let unexpected = ("Answered", "This answer does nothing here.")
}
