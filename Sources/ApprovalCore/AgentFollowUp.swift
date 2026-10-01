public enum AgentFollowUpKind: Sendable, Equatable {
  case nextStep
  case goodToKnow
}

public struct AgentFollowUp: Sendable, Equatable {
  public let host: Host
  public let kind: AgentFollowUpKind
  public let text: String
  public let offersMarkAsDone: Bool

  public init(host: Host, kind: AgentFollowUpKind, text: String, offersMarkAsDone: Bool) {
    self.host = host
    self.kind = kind
    self.text = text
    self.offersMarkAsDone = offersMarkAsDone
  }
}

public enum AgentFollowUps {
  public static let codexNextStep =
    "Open Codex in a terminal, not the desktop app, run /hooks and trust Countersign's hook. Codex sessions already open pick it up after /hooks or in a new session."
  public static let codexNextStepWithWaitingEntry =
    "Open Codex in a terminal, not the desktop app, run /hooks and trust Countersign's hooks. Codex sessions already open pick them up after /hooks or in a new session."

  public static func codexNextStep(hasWaitingEntry: Bool) -> String {
    hasWaitingEntry ? codexNextStepWithWaitingEntry : codexNextStep
  }

  public static func codexHasWaitingEntry(in file: Doctor.FileState) -> Bool {
    guard case .bytes(let bytes) = file else { return false }
    return !WaitingHookSetup.entries(in: bytes, host: .codex).isEmpty
  }

  public static let cursorGoodToKnow =
    "Only commands Cursor runs outside its sandbox, and MCP tool calls, get a panel."
  public static let antigravityGoodToKnow =
    "After you approve in the panel, Antigravity still asks once more in its own prompt until Google fixes antigravity-cli#1053."

  public static func current(
    host: Host, wiringStatus: HostWiringStatus, codexTrust: CodexHookTrustState = .unknown,
    codexHasWaitingEntry: Bool = false
  ) -> AgentFollowUp? {
    guard wiringStatus == .wired else { return nil }
    let nextStep = codexNextStep(hasWaitingEntry: codexHasWaitingEntry)
    switch host {
    case .claude:
      return nil
    case .codex:
      switch codexTrust {
      case .trusted, .markedDone:
        return nil
      case .unknown:
        return AgentFollowUp(
          host: .codex, kind: .nextStep, text: nextStep, offersMarkAsDone: true)
      case .pending(let reason, let offersMarkAsDone):
        return AgentFollowUp(
          host: .codex, kind: .nextStep,
          text: reason.map { "\($0) \(nextStep)" } ?? nextStep,
          offersMarkAsDone: offersMarkAsDone)
      }
    case .cursor:
      return AgentFollowUp(
        host: .cursor, kind: .goodToKnow, text: cursorGoodToKnow, offersMarkAsDone: false)
    case .antigravity:
      return AgentFollowUp(
        host: .antigravity, kind: .goodToKnow, text: antigravityGoodToKnow, offersMarkAsDone: false)
    }
  }

  public static func setupLines(
    wiring: [Host: HostWiringStatus], codexTrust: CodexHookTrustState, changedHosts: Set<Host>,
    uninstall: Bool, codexHasWaitingEntry: Bool = false
  ) -> [String] {
    guard !uninstall, !changedHosts.isEmpty else { return [] }
    return Host.allCases.compactMap { host in
      guard let status = wiring[host],
        let followUp = current(
          host: host, wiringStatus: status, codexTrust: codexTrust,
          codexHasWaitingEntry: codexHasWaitingEntry)
      else { return nil }
      switch followUp.kind {
      case .nextStep:
        return "Next step for \(host.displayName): \(followUp.text)"
      case .goodToKnow:
        guard changedHosts.contains(host) else { return nil }
        return "Good to know for \(host.displayName): \(followUp.text)"
      }
    }
  }
}
