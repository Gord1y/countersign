public enum HeadlessSessionGate {
  public enum Decision: Sendable, Equatable {
    case proceed
    case skip(kind: String)
  }

  public static func decide(
    registryEntry: SessionRegistry.Entry?,
    includeHeadlessSessions: Bool
  ) -> Decision {
    guard let registryEntry else {
      return .proceed
    }
    guard let kind = registryEntry.fields["kind"]?.stringValue else {
      return .proceed
    }
    guard kind != "interactive" else {
      return .proceed
    }
    guard !includeHeadlessSessions else {
      return .proceed
    }
    return .skip(kind: kind)
  }
}
