public enum PanelRunMode: Sendable, Equatable {
  case hook
  case test(TestPanelKind)

  public var isTest: Bool {
    guard case .test = self else { return false }
    return true
  }

  public var followsChat: Bool { !isTest }

  public var honorsPause: Bool { !isTest }

  public var honorsQuietTime: Bool { !isTest }

  public var handsBackBeforeTimeout: Bool { !isTest }

  public var honorsGracePeriod: Bool { !isTest }

  public var waitsItsTurn: Bool { !isTest }

  public var waitsForIdleOnArrival: Bool { !isTest }

  public var yieldsToOtherRequests: Bool { isTest }
}
