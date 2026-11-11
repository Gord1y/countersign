public enum DecisionsCommandLine: Sendable, Equatable {
  case list(limit: Int)
  case clear

  public static let usage = "usage: countersign decisions [--limit <1-200>] | clear"
  public static let empty = "no decisions yet"
  public static let cleared = "cleared"

  public static func parse(_ arguments: [String]) -> DecisionsCommandLine? {
    switch arguments.count {
    case 0:
      return .list(limit: CompanionMenu.recentDecisionLimit)
    case 1 where arguments[0] == "clear":
      return .clear
    case 2 where arguments[0] == "--limit":
      guard let limit = Int(arguments[1]), (1...DecisionHistory.keptEntries).contains(limit) else {
        return nil
      }
      return .list(limit: limit)
    default:
      return nil
    }
  }
}
