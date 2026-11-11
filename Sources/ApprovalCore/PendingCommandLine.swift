public enum PendingCommandLine: Sendable, Equatable {
  case list
  case answer(MenuAnswer, ticketID: String)

  public static let usage = "usage: countersign pending [show|deny|chat <id>]"

  public static func parse(_ arguments: [String]) -> PendingCommandLine? {
    switch arguments.count {
    case 0:
      return .list
    case 2:
      guard let answer = MenuAnswer(rawValue: arguments[0]) else { return nil }
      return .answer(answer, ticketID: arguments[1])
    default:
      return nil
    }
  }
}

public enum PendingCommandText {
  public static let empty = "no requests pending"
  public static let unknownTicket =
    "error: no pending request with that ID; run countersign pending"

  public static func notOffered(_ answer: MenuAnswer, offered: [MenuAnswer]) -> String {
    "error: this request offers only \(offered.map(\.rawValue).joined(separator: ", "))"
  }

  public static func line(for entry: WaitingEntry) -> String {
    let title = CompanionMenu.pendingRowTitle(for: entry)
    guard let ticketID = entry.ticketID else {
      return "-  \(title)  (cannot be answered here)"
    }
    let offered = MenuAnswer.offered(for: entry.summary).map(\.rawValue).joined(separator: ", ")
    return "\(ticketID)  \(title)  (\(offered))"
  }

  public static func sent(_ answer: MenuAnswer) -> String {
    switch answer {
    case .show: return "sent: showing it now"
    case .deny: return "sent: denied"
    case .chat: return "sent: answer in chat"
    }
  }
}

public enum PendingAnswerCheck: Sendable, Equatable {
  case send
  case unknownTicket
  case notOffered([MenuAnswer])

  public static func check(_ answer: MenuAnswer, ticketID: String, entries: [WaitingEntry])
    -> PendingAnswerCheck
  {
    guard let entry = entries.first(where: { $0.ticketID == ticketID }) else {
      return .unknownTicket
    }
    let offered = MenuAnswer.offered(for: entry.summary)
    return offered.contains(answer) ? .send : .notOffered(offered)
  }
}
