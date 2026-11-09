import Testing

@testable import ApprovalCore

@Suite struct PendingCommandLineTests {
  private let normal = TicketSummary(
    host: .claude, project: "shop-api", tool: "Bash", agentType: nil)
  private let checkpoint = TicketSummary(
    host: .claude, project: "shop-api", tool: "Context checkpoint", agentType: nil,
    isContextCheckpoint: true)
  private let noChat = TicketSummary(
    host: .claude, project: "shop-api", tool: "Bash", agentType: nil, answersInChat: false)

  @Test func parsesListAndEachAnswer() {
    #expect(PendingCommandLine.parse([]) == .list)
    #expect(PendingCommandLine.parse(["show", "0001-42"]) == .answer(.show, ticketID: "0001-42"))
    #expect(PendingCommandLine.parse(["deny", "0001-42"]) == .answer(.deny, ticketID: "0001-42"))
    #expect(PendingCommandLine.parse(["chat", "0001-42"]) == .answer(.chat, ticketID: "0001-42"))
  }

  @Test func rejectsApprovalsAndMalformedArguments() {
    for arguments in [["approve", "x"], ["allow", "x"], ["show"], ["show", "a", "b"], ["bogus"]] {
      #expect(PendingCommandLine.parse(arguments) == nil)
    }
  }

  @Test func linesListTheOfferedAnswersInMenuOrder() {
    #expect(
      PendingCommandText.line(for: WaitingEntry(summary: normal, ticketID: "0001-42"))
        == "0001-42  Claude Code · shop-api · Bash  (show, deny, chat)")
    #expect(
      PendingCommandText.line(for: WaitingEntry(summary: noChat, ticketID: "0001-42"))
        == "0001-42  Claude Code · shop-api · Bash  (show, deny)")
    #expect(
      PendingCommandText.line(for: WaitingEntry(summary: checkpoint, ticketID: "0002-43"))
        == "0002-43  Claude Code · shop-api · Context checkpoint  (show)")
  }

  @Test func aLineWithoutATicketCannotBeAnswered() {
    #expect(
      PendingCommandText.line(for: WaitingEntry(summary: normal))
        == "-  Claude Code · shop-api · Bash  (cannot be answered here)")
  }

  @Test func notOfferedNamesWhatIsOffered() {
    #expect(
      PendingCommandText.notOffered(.deny, offered: [.show])
        == "error: this request offers only show")
    #expect(
      PendingCommandText.notOffered(.chat, offered: [.show, .deny])
        == "error: this request offers only show, deny")
  }

  @Test func sentTextCoversEveryAnswer() {
    #expect(PendingCommandText.sent(.show) == "sent: showing it now")
    #expect(PendingCommandText.sent(.deny) == "sent: denied")
    #expect(PendingCommandText.sent(.chat) == "sent: answer in chat")
  }

  @Test func checkFindsTheTicketAndHonoursWhatIsOffered() {
    let entries = [
      WaitingEntry(summary: normal, ticketID: "0001-42"),
      WaitingEntry(summary: checkpoint, ticketID: "0002-43"),
      WaitingEntry(summary: noChat, ticketID: "0003-44"),
    ]

    #expect(PendingAnswerCheck.check(.deny, ticketID: "9999-1", entries: entries) == .unknownTicket)
    #expect(
      PendingAnswerCheck.check(.deny, ticketID: "0002-43", entries: entries) == .notOffered([.show])
    )
    #expect(
      PendingAnswerCheck.check(.chat, ticketID: "0003-44", entries: entries)
        == .notOffered([.show, .deny]))
    #expect(PendingAnswerCheck.check(.deny, ticketID: "0001-42", entries: entries) == .send)
  }

  @Test func noAnswerMeansApproval() {
    let names = MenuAnswer.allCases.map(\.rawValue)
    for forbidden in ["approve", "allow", "yes"] {
      #expect(!names.contains(forbidden))
    }
  }
}
