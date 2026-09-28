import Foundation
import Testing

@testable import ApprovalCore

private let hooksFile = "/Users/dev/.codex/hooks.json"
private let ourCommand = "/opt/homebrew/bin/countersign hook --host codex"
private let ours = "sha256:ours"
private let newer = "sha256:newer"
private let other = "sha256:other"
private let stale = "sha256:stale"

private func key(_ group: Int, _ handler: Int, event: String = "permission_request") -> String {
  "\(hooksFile):\(event):\(group):\(handler)"
}

private func record(
  at hookKey: String = key(0, 0), hashAtWrite: CodexHashAtWrite = .absent,
  learnedHash: String? = nil, markedDone: Bool = false, command: String = ourCommand
) -> CodexHookTrustRecord {
  CodexHookTrustRecord(
    hookKey: hookKey, command: command, hashAtWrite: hashAtWrite, learnedHash: learnedHash,
    markedDone: markedDone)
}

private func judge(
  _ record: CodexHookTrustRecord?, at currentKey: String? = key(0, 0),
  _ hashes: [String: String]?
) -> CodexTrustVerdict {
  CodexTrustVerdict.judge(
    record: record,
    current: currentKey.map {
      CodexHookTrustCurrent(hookKey: $0, command: ourCommand, hasMultipleEntries: false)
    },
    table: hashes.map { CodexTrustTable(trustedHashes: $0) })
}

private func state(
  _ record: CodexHookTrustRecord?, at currentKey: String? = key(0, 0),
  _ hashes: [String: String]?
) -> CodexHookTrustState {
  judge(record, at: currentKey, hashes).state
}

private func trusted(learning hash: String?) -> CodexTrustVerdict {
  CodexTrustVerdict(state: .trusted, newlyLearnedHash: hash)
}

private let pendingHere = CodexHookTrustState.pending(reason: nil, offersMarkAsDone: false)
private let pendingHereUnsure = CodexHookTrustState.pending(reason: nil, offersMarkAsDone: true)

private func pendingAdded(offersMarkAsDone: Bool) -> CodexHookTrustState {
  .pending(reason: CodexTrustVerdict.hookAddedBeforeReason, offersMarkAsDone: offersMarkAsDone)
}

private func pendingRemoved(offersMarkAsDone: Bool) -> CodexHookTrustState {
  .pending(reason: CodexTrustVerdict.hookRemovedBeforeReason, offersMarkAsDone: offersMarkAsDone)
}

@Suite struct CodexTrustVerdictTests {
  @Test func explainsAMoveInPlainWords() {
    #expect(
      CodexTrustVerdict.hookAddedBeforeReason
        == "Codex asks again because another hook was added before Countersign's.")
    #expect(
      CodexTrustVerdict.hookRemovedBeforeReason
        == "Codex asks again because a hook before Countersign's was removed.")
  }

  @Test func cannotTellWithoutARecordOrOurEntry() {
    #expect(
      judge(nil, [key(0, 0): ours]) == CodexTrustVerdict(state: .unknown, newlyLearnedHash: nil))
    #expect(state(record(), at: nil, [key(0, 0): ours]) == .unknown)
  }

  @Test func cannotTellOnceOurCommandChanged() {
    let moved = record(learnedHash: ours, markedDone: true, command: "/usr/local/bin/countersign")
    #expect(state(moved, [key(0, 0): ours]) == .unknown)
  }

  @Test func cannotTellWhenConfigTOMLCannotBeRead() {
    let learned = record(learnedHash: ours)
    #expect(state(learned, nil) == .unknown)
    for file: Doctor.FileState in [
      .missing, .unreadable("Permission denied"), .bytes([0xFF, 0xFE]),
      .bytes(Array("[hooks]\nstate = {}\n".utf8)),
    ] {
      let verdict = CodexTrustVerdict.judge(
        record: learned,
        current: CodexHookTrustCurrent(
          hookKey: key(0, 0), command: ourCommand, hasMultipleEntries: false),
        table: CodexTrustTable.read(file))
      #expect(verdict.state == .unknown)
    }
  }

  @Test func learnsTheHashCodexStoresOnceTheUserTrustsOurHook() {
    #expect(judge(record(), [key(0, 0): ours]) == trusted(learning: ours))
    #expect(
      judge(record(hashAtWrite: .stored(stale)), [key(0, 0): ours]) == trusted(learning: ours))
  }

  @Test func staysPendingWhileTheStoredHashIsTheOneSeenAtWrite() {
    #expect(state(record(), [:]) == pendingHere)
    #expect(state(record(hashAtWrite: .stored(stale)), [key(0, 0): stale]) == pendingHereUnsure)
    #expect(state(record(hashAtWrite: .stored(stale)), [:]) == pendingHereUnsure)
  }

  @Test func neverInfersTrustFromARecordWrittenWithoutReadingTheConfig() {
    let unread = record(hashAtWrite: .unread)
    #expect(
      judge(unread, [:]) == CodexTrustVerdict(state: pendingHereUnsure, newlyLearnedHash: nil))
    #expect(
      judge(unread, [key(0, 0): ours])
        == CodexTrustVerdict(state: pendingHereUnsure, newlyLearnedHash: nil))
    #expect(
      judge(record(hashAtWrite: .unread, markedDone: true), [key(0, 0): ours])
        == CodexTrustVerdict(state: .markedDone, newlyLearnedHash: nil))
    #expect(state(unread, at: key(1, 0), [key(1, 0): ours]) == pendingAdded(offersMarkAsDone: true))
    #expect(
      judge(record(hashAtWrite: .unread, learnedHash: ours), [key(0, 0): ours])
        == trusted(learning: nil))
  }

  @Test func neverLearnsFromAMarkMadeWhileTheConfigWasUnreadable() {
    let beforeTheMove = record(at: key(0, 0), hashAtWrite: .absent)
    let marked = CodexHookTrust.markedRecord(
      existing: beforeTheMove,
      current: CodexHookTrustCurrent(
        hookKey: key(1, 0), command: ourCommand, hasMultipleEntries: false),
      table: nil)
    let atTheMark = judge(marked, at: key(1, 0), [key(0, 0): other, key(1, 0): other])
    #expect(atTheMark == CodexTrustVerdict(state: .markedDone, newlyLearnedHash: nil))
    let persisted = atTheMark.newlyLearnedHash.map(marked.learning) ?? marked
    #expect(
      state(persisted, at: key(0, 0), [key(0, 0): other, key(1, 0): other])
        == pendingRemoved(offersMarkAsDone: true))
  }

  @Test func staysTrustedOnceTheHashIsLearned() {
    #expect(judge(record(learnedHash: ours), [key(0, 0): ours]) == trusted(learning: nil))
  }

  @Test func letsTheLearnedHashAloneDecide() {
    #expect(state(record(learnedHash: ours), [key(0, 0): other]) == pendingHere)
    let movedBack = record(learnedHash: ours)
    #expect(state(movedBack, [key(0, 0): other, key(1, 0): ours]) == pendingHere)
  }

  @Test func staysTrustedWhenAHookIsAddedForAnotherEvent() {
    let hashes = [key(0, 0): ours, key(0, 0, event: "pre_tool_use"): other]
    #expect(state(record(learnedHash: ours), hashes) == .trusted)
    #expect(judge(record(), hashes) == trusted(learning: ours))
  }

  @Test func staysTrustedWhenAHookIsAddedAfterOurs() {
    let learned = record(learnedHash: ours)
    #expect(state(learned, [key(0, 0): ours, key(0, 1): other]) == .trusted)
    #expect(state(learned, [key(0, 0): ours, key(1, 0): other]) == .trusted)
  }

  @Test func asksAgainWithTheReasonWhenAHookIsInsertedBeforeOurs() {
    let learned = record(learnedHash: ours)
    #expect(
      state(learned, at: key(1, 0), [key(0, 0): ours]) == pendingAdded(offersMarkAsDone: false))
    #expect(
      state(learned, at: key(0, 1), [key(0, 0): ours]) == pendingAdded(offersMarkAsDone: false))
    #expect(
      state(record(), at: key(1, 0), [key(0, 0): ours]) == pendingAdded(offersMarkAsDone: true))
  }

  @Test func saysSoWhenAHookBeforeOursIsRemoved() {
    let learned = record(at: key(1, 0), learnedHash: ours)
    #expect(
      state(learned, at: key(0, 0), [key(0, 0): other]) == pendingRemoved(offersMarkAsDone: false))
    #expect(
      state(record(at: key(1, 0)), at: key(0, 3), [:]) == pendingRemoved(offersMarkAsDone: true))
  }

  @Test func isTrustedOnceTheUserTrustsOursAtItsNewKey() {
    let learned = record(learnedHash: ours)
    #expect(
      judge(learned, at: key(1, 0), [key(0, 0): ours, key(1, 0): ours]) == trusted(learning: nil))
  }

  @Test func trustingOnlyTheNewHookChangesNothingForOurs() {
    let learned = record(learnedHash: ours)
    #expect(
      state(learned, at: key(1, 0), [key(0, 0): ours])
        == state(learned, at: key(1, 0), [key(0, 0): other]))
    #expect(
      state(record(), at: key(1, 0), [:]) == state(record(), at: key(1, 0), [key(0, 0): other]))
    #expect(
      state(learned, [key(0, 0): ours]) == state(learned, [key(0, 0): ours, key(0, 1): other]))
  }

  @Test func startsOverWhenCountersignRewritesItsHook() {
    let rewritten = record(hashAtWrite: .stored(ours))
    #expect(state(rewritten, [key(0, 0): ours]) == pendingHereUnsure)
    #expect(judge(rewritten, [key(0, 0): newer]) == trusted(learning: newer))
  }

  @Test func keepsAMarkWhileOurKeyIsUnchanged() {
    let marked = record(hashAtWrite: .stored(stale), markedDone: true)
    #expect(state(marked, nil) == .markedDone)
    #expect(state(marked, [key(0, 0): stale]) == .markedDone)
    #expect(judge(marked, [key(0, 0): ours]) == trusted(learning: ours))
    #expect(
      state(marked, at: key(1, 0), [key(0, 0): stale]) == pendingAdded(offersMarkAsDone: true))
    #expect(state(marked, at: nil, [key(0, 0): stale]) == .unknown)
    #expect(state(record(learnedHash: ours, markedDone: true), [key(0, 0): other]) == .markedDone)
  }

  @Test func readsAnotherHooksFileOrEventOnlyThroughTheLearnedHash() {
    let elsewhere = "/Users/dev/other/hooks.json:permission_request:1:0"
    #expect(state(record(), at: elsewhere, [:]) == .unknown)
    #expect(state(record(learnedHash: ours), at: elsewhere, [elsewhere: ours]) == .trusted)
    #expect(state(record(learnedHash: ours), at: elsewhere, [:]) == pendingHere)
    #expect(state(record(), at: key(0, 0, event: "pre_tool_use"), [:]) == .unknown)
  }

  @Test(arguments: [
    ("countersign", key(0, 0)),
    (key(0, 0), "\(hooksFile):permission_request:0:x"),
    (key(0, 0), "\(hooksFile):permission_request:0:"),
    (key(0, 0), "\(hooksFile):permission_request:x:0"),
    (key(0, 0), "0:0"),
  ])
  func cannotTellWithAKeyThatIsNotAHookSlot(recorded: String, current: String) {
    #expect(state(record(at: recorded), at: current, [:]) == .unknown)
  }
}
