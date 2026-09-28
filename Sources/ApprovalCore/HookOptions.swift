public struct HookOptions: Sendable, Equatable {
  public var host: Host

  public init(host: Host) {
    self.host = host
  }

  public static func parse(_ arguments: [String]) -> HookOptions? {
    guard arguments.count == 2, arguments[0] == "--host",
      let host = Host(rawValue: arguments[1])
    else { return nil }
    return HookOptions(host: host)
  }
}
