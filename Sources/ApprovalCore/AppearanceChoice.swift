public enum AppearanceChoice: String, Sendable, Equatable, CaseIterable {
  case system
  case light
  case dark

  public var title: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }
}
