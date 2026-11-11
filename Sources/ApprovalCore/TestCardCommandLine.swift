public enum TestCardKindName: String, CaseIterable, Sendable {
  case notice
  case approval
}

public enum TestCardCommandLine {
  public static let usage = "usage: countersign test-card notice|approval"

  public static func parse(_ arguments: [String]) -> TestCardKindName? {
    guard arguments.count == 1 else { return nil }
    return TestCardKindName(rawValue: arguments[0])
  }
}
