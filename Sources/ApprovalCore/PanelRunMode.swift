public enum PanelRunMode: Sendable, Equatable {
  case hook
  case test(TestPanelKind)
  case checkpoint

  public var isTest: Bool {
    guard case .test = self else { return false }
    return true
  }

  public var followsChat: Bool { self == .hook }

  public var honorsPause: Bool { !isTest }

  public var honorsQuietTime: Bool { !isTest }

  public var handsBackBeforeTimeout: Bool { self == .hook }

  public var honorsGracePeriod: Bool { self == .hook }

  public var waitsItsTurn: Bool { !isTest }

  public var waitsForIdleOnArrival: Bool { !isTest }

  public var yieldsToOtherRequests: Bool { isTest }

  public var usesHandoffApps: Bool { self != .checkpoint }

  public var waitsForApprovalsFirst: Bool { self == .checkpoint }
}
