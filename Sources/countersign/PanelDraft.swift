import ApprovalCore
import Foundation

enum PermissionFooterState: Sendable, Equatable {
  case `default`
  case deny
}

enum PanelDraftField: Hashable, Sendable {
  case denyReason
  case planFeedback
  case other(Int)
  case notes(Int)
}

@MainActor
@Observable
final class PanelDraft {
  var permissionFooter = PermissionFooterState.default
  var denyReason = ""
  var revealedGaps: [Int: [Int: GapRevealState]] = [:]
  var planMode: PlanApprovalMode
  var isWritingPlanFeedback = false
  var planFeedback = ""
  var questionAnswers: [QuestionAnswer]
  var questionTab = 0
  var questionLastClickedOption: [Int: Int] = [:]
  var questionNotesExpanded: [Int: Bool] = [:]
  var checkpointChoice: ContextCheckpointChoice
  var focusedField: PanelDraftField?
  @ObservationIgnored var scrollOffset: CGFloat = 0
  @ObservationIgnored var fieldSelection: NSRange?

  init(request: ApprovalRequest, modeAfterPlan: PlanApprovalMode) {
    planMode = modeAfterPlan
    switch request.kind {
    case .questions(let questions):
      questionAnswers = questions.map { _ in QuestionAnswer() }
      checkpointChoice = .continueWorking
    case .contextCheckpoint(let prompt):
      questionAnswers = []
      checkpointChoice = ContextCheckpointChoice.highlighted(for: prompt.level)
    case .permission, .plan:
      questionAnswers = []
      checkpointChoice = .continueWorking
    }
  }
}
