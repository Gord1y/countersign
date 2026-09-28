public enum AppLaunchMode: Sendable, Equatable {
  case app
  case cli

  public static let bundleIdentifier = "dev.gord1y.countersign"

  public static func detect(bundleIdentifier: String?, arguments: [String]) -> AppLaunchMode {
    guard bundleIdentifier == Self.bundleIdentifier else { return .cli }
    let remaining = arguments.filter { !$0.hasPrefix("-psn_") }
    return remaining.isEmpty ? .app : .cli
  }
}
