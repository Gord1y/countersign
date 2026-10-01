import ApprovalCore

enum TestCornerCardKind: CaseIterable {
  case notice
  case approval

  var title: String {
    switch self {
    case .notice: "Notice"
    case .approval: "Approval"
    }
  }

  var help: String {
    switch self {
    case .notice: "Show a test waiting notice"
    case .approval: "Show a test approval card"
    }
  }

  var accessibilityTitle: String {
    switch self {
    case .notice: "Countersign test notice"
    case .approval: "Countersign test approval card"
    }
  }

  @MainActor
  var model: CornerCardModel {
    switch self {
    case .notice:
      .waitingNotice(hostName: "Codex", projectName: "Countersign test", offersGoThere: true)
    case .approval:
      .approval(hostName: "Cursor", projectName: "Countersign test")
    }
  }
}

enum TestCornerCardOutcome {
  case shown
  case alreadyUp
  case noFreeSlot
}

@MainActor
final class TestCornerCards {
  static let lifetime: Duration = .seconds(20)
  static let noFreeSlotMessage = "Both card spots are taken; close a card first."

  private var cards: [TestCornerCardKind: CornerCard] = [:]
  private var expiries: [TestCornerCardKind: Task<Void, Never>] = [:]

  func show(
    _ kind: TestCornerCardKind, store: WaitingStore, appearance: AppearanceChoice,
    onShowTestPanel: @escaping @MainActor () -> Void
  ) -> TestCornerCardOutcome {
    guard cards[kind] == nil else { return .alreadyUp }
    let onAction: @MainActor () -> Void = { [weak self] in
      self?.close(kind)
      if kind == .approval {
        onShowTestPanel()
      }
    }
    let onDismiss: @MainActor () -> Void = { [weak self] in self?.close(kind) }
    guard
      let card = CornerCard.inFreeSlot(
        of: store, model: kind.model, accessibilityTitle: kind.accessibilityTitle,
        appearance: appearance, onAction: onAction, onDismiss: onDismiss)
    else { return .noFreeSlot }
    cards[kind] = card
    card.show()
    expiries[kind] = Task { [weak self] in
      try? await Task.sleep(for: Self.lifetime)
      guard !Task.isCancelled else { return }
      self?.close(kind)
    }
    return .shown
  }

  func close(_ kind: TestCornerCardKind) {
    expiries[kind]?.cancel()
    expiries[kind] = nil
    cards[kind]?.close()
    cards[kind] = nil
  }

  func closeAll() {
    for kind in TestCornerCardKind.allCases {
      close(kind)
    }
  }
}
