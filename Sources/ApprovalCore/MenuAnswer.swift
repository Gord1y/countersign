import Darwin
import Foundation

public enum MenuAnswer: String, Sendable, Equatable, CaseIterable {
  case show
  case deny
  case chat

  static let fileSuffix = ".answer"

  public init?(fileContent: Data) {
    guard let text = String(data: fileContent, encoding: .utf8) else { return nil }
    self.init(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  public var fileContent: Data {
    Data("\(rawValue)\n".utf8)
  }

  public var title: String {
    switch self {
    case .show: return "Show Now"
    case .deny: return "Deny"
    case .chat: return "Answer in Chat"
    }
  }

  public var outcome: ApprovalOutcome? {
    switch self {
    case .show: return nil
    case .deny: return .deny(reason: "", interrupt: false)
    case .chat: return .noDecision
    }
  }

  public static func offered(for summary: TicketSummary?) -> [MenuAnswer] {
    guard let summary, !summary.isContextCheckpoint else { return [.show] }
    guard summary.answersInChat else { return [.show, .deny] }
    return allCases
  }

  static func fileName(ticketID: String) -> String {
    "\(ticketID)\(fileSuffix)"
  }

  static func ticketID(ofFileName name: String) -> String? {
    guard name.hasSuffix(fileSuffix) else { return nil }
    let ticketID = String(name.dropLast(fileSuffix.count))
    guard Ticket.parseFileName("\(ticketID)\(Ticket.fileSuffix)") != nil else { return nil }
    return ticketID
  }
}

extension TicketQueue {
  public func sendMenuAnswer(_ answer: MenuAnswer, toTicketID ticketID: String) throws -> Bool {
    let ticketName = "\(ticketID)\(Ticket.fileSuffix)"
    guard Ticket.parseFileName(ticketName) != nil,
      FileManager.default.fileExists(atPath: directory.appendingPathComponent(ticketName).path)
    else { return false }
    try writeAtomically(answer.fileContent, named: MenuAnswer.fileName(ticketID: ticketID))
    return true
  }

  public func takeMenuAnswer(for ticket: Ticket) -> MenuAnswer? {
    let url = answerURL(ticketID: ticket.id)
    guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
    unlink(url.path)
    return MenuAnswer(fileContent: data)
  }

  func answerURL(ticketID: String) -> URL {
    directory.appendingPathComponent(MenuAnswer.fileName(ticketID: ticketID))
  }

  func removeAnswers(of ticketIDs: [String], keeping liveIDs: Set<String>) {
    for ticketID in ticketIDs where !liveIDs.contains(ticketID) {
      let ticketPath = directory.appendingPathComponent("\(ticketID)\(Ticket.fileSuffix)").path
      guard !FileManager.default.fileExists(atPath: ticketPath) else { continue }
      unlink(answerURL(ticketID: ticketID).path)
    }
  }
}
