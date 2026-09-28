public struct CodexTrustVerdict: Sendable, Equatable {
  public static let hookAddedBeforeReason =
    "Codex asks again because another hook was added before Countersign's."
  public static let hookRemovedBeforeReason =
    "Codex asks again because a hook before Countersign's was removed."

  public let state: CodexHookTrustState
  public let newlyLearnedHash: String?

  public static func judge(
    record: CodexHookTrustRecord?, current: CodexHookTrustCurrent?, table: CodexTrustTable?
  ) -> CodexTrustVerdict {
    guard let record, let current, record.command == current.command else {
      return verdict(.unknown)
    }
    let atRecordedKey = record.hookKey == current.hookKey
    let marked = record.markedDone && atRecordedKey
    guard let table else { return verdict(marked ? .markedDone : .unknown) }
    let stored = table.trustedHashes[current.hookKey]
    if let learned = record.learnedHash {
      if stored == learned {
        return verdict(.trusted)
      }
      if marked {
        return verdict(.markedDone)
      }
      return verdict(
        .pending(
          reason: moveReason(from: record.hookKey, to: current.hookKey), offersMarkAsDone: false))
    }
    if atRecordedKey {
      if let stored, record.hashAtWrite != .unread, record.hashAtWrite != .stored(stored) {
        return CodexTrustVerdict(state: .trusted, newlyLearnedHash: stored)
      }
      return verdict(
        marked
          ? .markedDone : .pending(reason: nil, offersMarkAsDone: record.hashAtWrite != .absent))
    }
    guard let reason = moveReason(from: record.hookKey, to: current.hookKey) else {
      return verdict(.unknown)
    }
    return verdict(.pending(reason: reason, offersMarkAsDone: true))
  }

  private static func verdict(_ state: CodexHookTrustState) -> CodexTrustVerdict {
    CodexTrustVerdict(state: state, newlyLearnedHash: nil)
  }

  private static func moveReason(from recordedKey: String, to currentKey: String) -> String? {
    guard let recorded = HookSlot(key: recordedKey), let current = HookSlot(key: currentKey),
      recorded.list == current.list,
      (recorded.group, recorded.handler) != (current.group, current.handler)
    else { return nil }
    return (current.group, current.handler) > (recorded.group, recorded.handler)
      ? hookAddedBeforeReason : hookRemovedBeforeReason
  }
}

private struct HookSlot {
  let list: Substring
  let group: Int
  let handler: Int

  init?(key: String) {
    guard let handlerColon = key.lastIndex(of: ":"),
      let handler = Self.index(key[key.index(after: handlerColon)...])
    else { return nil }
    let head = key[..<handlerColon]
    guard let groupColon = head.lastIndex(of: ":"),
      let group = Self.index(head[head.index(after: groupColon)...])
    else { return nil }
    list = head[..<groupColon]
    self.group = group
    self.handler = handler
  }

  private static func index(_ text: Substring) -> Int? {
    guard !text.isEmpty, text.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
    return Int(text)
  }
}
