import AppKit
import ApprovalCore
import Foundation

@MainActor
final class ColdCacheCardController {
  private struct ShownCard {
    let card: CornerCard
    let model: CornerCardModel
    var candidate: ColdCacheCandidate
  }

  private let paths: AppPaths
  private let log: EventLog
  private let waitingStore: WaitingStore
  private var shown: ShownCard?
  private var ledger = ColdCacheWarningLedger()
  private var latestSettings: Settings?

  init(paths: AppPaths, log: EventLog) {
    self.paths = paths
    self.log = log
    waitingStore = WaitingStore(directory: paths.waitingDirectory)
  }

  func tick(settings: Settings, isHeld: Bool, now: Date) {
    latestSettings = settings
    let candidates = dueCandidates(settings: settings, isHeld: isHeld, now: now)
    let hasApprovalClaim = waitingStore.liveApprovalClaim() != nil
    if let current = shown {
      reconcile(
        current, candidates: candidates, isHeld: isHeld, hasApprovalClaim: hasApprovalClaim)
    }
    guard shown == nil, !hasApprovalClaim else { return }
    guard let next = candidates.first(where: { !ledger.isWarned($0) }) else { return }
    show(next, appearance: settings.appearance)
  }

  private func dueCandidates(settings: Settings, isHeld: Bool, now: Date) -> [ColdCacheCandidate] {
    guard !isHeld else { return [] }
    return ColdCacheWarning.candidates(
      store: ContextCheckpointStore(directory: paths.contextCheckpointsDirectory),
      isIdle: {
        ColdCacheWarning.isIdle(sessionID: $0, sessionsDirectory: paths.claudeSessionsDirectory)
      },
      settings: settings.contextCheckpoints, now: now)
  }

  private func reconcile(
    _ current: ShownCard, candidates: [ColdCacheCandidate], isHeld: Bool, hasApprovalClaim: Bool
  ) {
    let sessionID = current.candidate.sessionID
    if isHeld {
      close()
      ledger.forget(sessionID: sessionID)
      log.write("cold cache card: hidden (paused or quiet time)")
      return
    }
    guard
      let fresh = candidates.first(where: {
        $0.sessionID == sessionID && $0.lastActivity == current.candidate.lastActivity
      })
    else {
      close()
      log.write("cold cache card: closed (no longer due)")
      return
    }
    if hasApprovalClaim, current.card.slot == WaitingStore.slotCount - 1 {
      close()
      ledger.forget(sessionID: sessionID)
      log.write("cold cache card: hidden (approval waiting)")
      return
    }
    current.model.leadText = ColdCacheWarning.leadText(
      tokens: fresh.tokens, secondsLeft: fresh.secondsLeft)
    shown?.candidate = fresh
  }

  private func show(_ candidate: ColdCacheCandidate, appearance: AppearanceChoice) {
    let model = CornerCardModel.coldCache(
      tokens: candidate.tokens, secondsLeft: candidate.secondsLeft,
      projectName: candidate.project)
    guard
      let card = CornerCard.inFreeSlot(
        of: waitingStore, model: model, accessibilityTitle: "Countersign cache warning",
        appearance: appearance, onAction: { [weak self] in self?.copyHandoffPrompt() },
        onDismiss: { [weak self] in self?.dismiss() })
    else { return }
    shown = ShownCard(card: card, model: model, candidate: candidate)
    ledger.markWarned(candidate)
    card.show()
    log.write("cold cache card: shown")
  }

  private func copyHandoffPrompt() {
    guard let current = shown, let settings = latestSettings?.contextCheckpoints else { return }
    let prompt = ContextCheckpointNotes.render(
      settings.notes.handoff, tokens: current.candidate.tokens, handoffFile: settings.handoffFile,
      compactions: 0)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let copied = pasteboard.setString(prompt, forType: .string)
    close()
    log.write(
      copied
        ? "cold cache card: copied the handoff prompt"
        : "cold cache card: failed to copy the handoff prompt")
  }

  private func dismiss() {
    close()
    log.write("cold cache card: dismissed")
  }

  private func close() {
    shown?.card.close()
    shown = nil
  }
}
