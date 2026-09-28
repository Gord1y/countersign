public enum TestPanelRefusal: Sendable, Equatable, CaseIterable {
  case panelOnScreen
  case requestWaiting

  public var message: String {
    switch self {
    case .panelOnScreen: return "a panel is already on screen; answer it first"
    case .requestWaiting: return "a request is waiting for a panel; answer it first"
    }
  }
}

public enum TestPanelAdmission: Sendable, Equatable {
  case show
  case refuse(TestPanelRefusal)

  public static func decide(panelOnScreen: Bool, otherTickets: Int) -> TestPanelAdmission {
    if panelOnScreen {
      return .refuse(.panelOnScreen)
    }
    if otherTickets > 0 {
      return .refuse(.requestWaiting)
    }
    return .show
  }
}
