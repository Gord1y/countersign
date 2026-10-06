public enum HookEventOption: String, Sendable, Equatable {
  case waiting
}

public struct HookOptions: Sendable, Equatable {
  public var host: Host
  public var event: HookEventOption?

  public init(host: Host, event: HookEventOption? = nil) {
    self.host = host
    self.event = event
  }

  public static func parse(_ arguments: [String]) -> HookOptions? {
    guard arguments.count == 2 || arguments.count == 4, arguments[0] == "--host",
      let host = Host(rawValue: arguments[1])
    else { return nil }
    guard arguments.count == 4 else { return HookOptions(host: host) }
    guard arguments[2] == "--event", let event = HookEventOption(rawValue: arguments[3]) else {
      return nil
    }
    return HookOptions(host: host, event: event)
  }
}
