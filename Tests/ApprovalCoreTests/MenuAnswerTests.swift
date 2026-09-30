import Darwin
import Foundation
import Testing

@testable import ApprovalCore

@Suite struct MenuAnswerTests {
  @Test func eachAnswerRoundTripsThroughItsFileContent() {
    for answer in MenuAnswer.allCases {
      #expect(MenuAnswer(fileContent: answer.fileContent) == answer)
    }
    #expect(MenuAnswer.show.fileContent == Data("show\n".utf8))
    #expect(MenuAnswer.deny.fileContent == Data("deny\n".utf8))
    #expect(MenuAnswer.chat.fileContent == Data("chat\n".utf8))
  }

  @Test func parsingTrimsWhitespaceAndIgnoresUnknownContent() {
    #expect(MenuAnswer(fileContent: Data("deny".utf8)) == .deny)
    #expect(MenuAnswer(fileContent: Data("  chat \r\n".utf8)) == .chat)
    let unknown = [
      "", "\n", "approve", "SHOW", "deny please", "show\nchat", "{\"answer\":\"deny\"}",
    ]
    for content in unknown {
      #expect(MenuAnswer(fileContent: Data(content.utf8)) == nil, "\(content)")
    }
    #expect(MenuAnswer(fileContent: Data([0xFF, 0xFE])) == nil)
  }

  @Test func titlesAreTheMenuWording() {
    #expect(MenuAnswer.show.title == "Show Now")
    #expect(MenuAnswer.deny.title == "Deny")
    #expect(MenuAnswer.chat.title == "Answer in Chat")
  }

  @Test func denyAndChatSendWhatThePanelSends() {
    #expect(
      MenuAnswer.deny.outcome
        == .deny(message: ApprovalOutcome.defaultDenyMessage, interrupt: false))
    #expect(MenuAnswer.chat.outcome == .noDecision)
    #expect(MenuAnswer.show.outcome == nil)
  }

  @Test func checkpointsAndUnreadableTicketsAreOfferedOnlyShowNow() {
    let request = TicketSummary(host: .codex, project: "shop-api", tool: "Bash", agentType: nil)
    let testPanel = TicketSummary(
      host: .claude, project: "Countersign test", tool: "Bash", agentType: nil, isTestPanel: true)
    let checkpoint = TicketSummary(
      host: .claude, project: "shop-api", tool: "Context checkpoint", agentType: nil,
      isContextCheckpoint: true)

    #expect(MenuAnswer.offered(for: request) == [.show, .deny, .chat])
    #expect(MenuAnswer.offered(for: testPanel) == [.show, .deny, .chat])
    #expect(MenuAnswer.offered(for: checkpoint) == [.show])
    #expect(MenuAnswer.offered(for: nil) == [.show])
  }

  @Test func theTicketIDIsItsFileNameWithoutTheSuffix() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)

    #expect("\(ticket.id).json" == ticket.fileName)
    #expect(ticket.id == Ticket.fileName(timestamp: ticket.timestamp, pid: ticket.pid).dropLast(5))
  }

  @Test func anAnswerIsWrittenAtomicallyReadOnceAndDeleted() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)

    #expect(temporary.queue.takeMenuAnswer(for: ticket) == nil)
    #expect(try temporary.queue.sendMenuAnswer(.deny, toTicketID: ticket.id))
    #expect(Self.everyName(in: temporary) == ["\(ticket.id).answer", ticket.fileName].sorted())
    #expect(
      try Data(contentsOf: temporary.directory.appendingPathComponent("\(ticket.id).answer"))
        == Data("deny\n".utf8))

    #expect(temporary.queue.takeMenuAnswer(for: ticket) == .deny)
    #expect(!temporary.fileExists("\(ticket.id).answer"))
    #expect(temporary.queue.takeMenuAnswer(for: ticket) == nil)
  }

  @Test func aLaterAnswerReplacesAnUnreadOne() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)

    #expect(try temporary.queue.sendMenuAnswer(.show, toTicketID: ticket.id))
    #expect(try temporary.queue.sendMenuAnswer(.chat, toTicketID: ticket.id))
    #expect(temporary.queue.takeMenuAnswer(for: ticket) == .chat)
  }

  @Test func unknownContentIsDeletedAndIgnored() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)
    try Data("approve\n".utf8).write(
      to: temporary.directory.appendingPathComponent("\(ticket.id).answer"))

    #expect(temporary.queue.takeMenuAnswer(for: ticket) == nil)
    #expect(!temporary.fileExists("\(ticket.id).answer"))
  }

  @Test func anAnswerForAMissingOrMalformedTicketIsNotSent() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)
    let missing = String(Ticket.fileName(timestamp: 1, pid: getpid()).dropLast(5))

    for ticketID in [missing, "", "notes", "../\(ticket.id)", "\(ticket.id).json", ".\(ticket.id)"]
    {
      #expect(try !temporary.queue.sendMenuAnswer(.deny, toTicketID: ticketID), "\(ticketID)")
    }
    #expect(Self.everyName(in: temporary) == [ticket.fileName])
  }

  @Test func removingATicketRemovesItsAnswer() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)
    #expect(try temporary.queue.sendMenuAnswer(.show, toTicketID: ticket.id))

    #expect(Self.everyName(in: temporary).count == 2)

    temporary.queue.remove(ticket)

    #expect(Self.everyName(in: temporary).isEmpty)
  }

  private static func everyName(in temporary: TemporaryQueue) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: temporary.directory.path)) ?? [])
      .sorted()
  }

  @Test func aListingRemovesTheAnswersOfDeadAndVanishedTicketsAndKeepsTheRest() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let dead = try ChildProcess.deadPid()
    let deadTicket = try temporary.writeTicket(timestamp: 1, pid: dead, processStart: nil)
    let deadID = String(deadTicket.dropLast(5))
    let vanishedID = String(Ticket.fileName(timestamp: 2, pid: getpid()).dropLast(5))
    let live = try temporary.queue.enqueue(.probe)
    for ticketID in [deadID, vanishedID] {
      try Data("deny\n".utf8).write(
        to: temporary.directory.appendingPathComponent("\(ticketID).answer"))
    }
    #expect(try temporary.queue.sendMenuAnswer(.chat, toTicketID: live.id))
    let foreign = ["notes.answer", ".\(live.id).answer.tmp", "\(deadID).answer.bak", "x-1.answer"]
    for name in foreign {
      try Data("deny\n".utf8).write(to: temporary.directory.appendingPathComponent(name))
    }

    #expect(temporary.queue.liveTickets() == [live])
    #expect(!temporary.fileExists(deadTicket))
    #expect(!temporary.fileExists("\(deadID).answer"))
    #expect(!temporary.fileExists("\(vanishedID).answer"))
    #expect(temporary.fileExists("\(live.id).answer"))
    for name in foreign {
      #expect(temporary.fileExists(name), "\(name)")
    }
    #expect(temporary.queue.takeMenuAnswer(for: live) == .chat)
  }

  @Test func answerFilesNeverCountAsTickets() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)
    #expect(try temporary.queue.sendMenuAnswer(.deny, toTicketID: ticket.id))

    #expect(temporary.queue.waitingCount(excluding: ticket) == 0)
    #expect(
      temporary.queue.waitingEntries() == [WaitingEntry(summary: .probe, ticketID: ticket.id)])
  }
}

@Suite struct ShowNowTests {
  @Test func positionsCompareKeyByKey() {
    let early = QueuePosition.arrival(timestamp: 100, pid: 9)
    let tied = QueuePosition.arrival(timestamp: 100, pid: 10)
    let late = QueuePosition.arrival(timestamp: 200, pid: 1)
    let olderFront = QueuePosition.front(at: 500)
    let newerFront = QueuePosition.front(at: 600)
    let olderBehindEarly = early.behind(at: 500)
    let newerBehindEarly = early.behind(at: 600)

    #expect(early < tied && tied < late)
    #expect(newerFront < olderFront && olderFront < early)
    #expect(early < newerBehindEarly && newerBehindEarly < olderBehindEarly)
    #expect(olderBehindEarly < tied)
    #expect(olderFront < olderFront.behind(at: 700) && olderFront.behind(at: 700) < early)
    #expect(newerFront < olderFront.behind(at: 700))
    #expect(!(early < early))
  }

  @Test func withNothingOnScreenShowNowMovesTheTicketToTheFront() throws {
    let queue = try ThreeTickets()
    defer { queue.temporary.remove() }

    let result = try queue.temporary.queue.showNow(queue.last, isOnScreen: { _ in false })

    #expect(result.place == .front)
    #expect(result.ticket.fileName == queue.last.fileName)
    #expect(result.ticket.menuPosition != nil)
    #expect(queue.order() == [queue.last, queue.first, queue.middle].map(\.fileName))
    #expect(queue.temporary.queue.liveTickets().first == result.ticket)
  }

  @Test func withAPanelOnScreenShowNowMakesTheTicketNextAfterIt() throws {
    let queue = try ThreeTickets()
    defer { queue.temporary.remove() }
    let first = queue.first

    let result = try queue.temporary.queue.showNow(
      queue.last, isOnScreen: { $0.fileName == first.fileName })

    #expect(result.place == .behindShownPanel)
    #expect(queue.order() == [queue.first, queue.last, queue.middle].map(\.fileName))
    #expect(queue.temporary.queue.nextInLine(after: first)?.fileName == queue.last.fileName)
  }

  @Test func theNewestShowNowGoesFirst() throws {
    let queue = try ThreeTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    _ = try tickets.showNow(queue.last, isOnScreen: { _ in false })
    _ = try tickets.showNow(queue.middle, isOnScreen: { _ in false })
    #expect(queue.order() == [queue.middle, queue.last, queue.first].map(\.fileName))
  }

  @Test func theNewestShowNowIsNextAfterThePanelOnScreen() throws {
    let queue = try ThreeTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue
    let first = queue.first

    _ = try tickets.showNow(queue.middle, isOnScreen: { $0.fileName == first.fileName })
    _ = try tickets.showNow(queue.last, isOnScreen: { $0.fileName == first.fileName })
    #expect(queue.order() == [queue.first, queue.last, queue.middle].map(\.fileName))
  }

  @Test func aPanelShownFromTheMenuKeepsItsPlaceWhenAnotherIsShownAfterIt() throws {
    let queue = try ThreeTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let shown = try tickets.showNow(queue.last, isOnScreen: { _ in false }).ticket
    _ = try tickets.showNow(queue.middle, isOnScreen: { $0.fileName == shown.fileName })

    #expect(queue.order() == [queue.last, queue.middle, queue.first].map(\.fileName))
  }

  @Test func aLeaseHolderIsOvertakenOnlyByATicketShownFromTheMenu() throws {
    let queue = try ThreeTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue
    let first = queue.first

    #expect(!tickets.isOvertakenFromMenu(queue.first))
    #expect(!tickets.isOvertakenFromMenu(queue.middle))

    _ = try tickets.showNow(queue.middle, isOnScreen: { $0.fileName == first.fileName })
    #expect(!tickets.isOvertakenFromMenu(queue.first))

    let front = try tickets.showNow(queue.last, isOnScreen: { _ in false }).ticket
    #expect(tickets.isOvertakenFromMenu(queue.first))
    #expect(!tickets.isOvertakenFromMenu(front))
  }

  @Test func theNewPlaceIsStoredInTheTicketAndSurvivesARestore() throws {
    let queue = try ThreeTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let moved = try tickets.showNow(queue.last, isOnScreen: { _ in false }).ticket
    let data = try Data(contentsOf: tickets.url(for: moved))
    let content = try JSONDecoder().decode(TicketContent.self, from: data)
    #expect(content.menuPosition == moved.menuPosition)
    #expect(content.summary == queue.last.summary)
    #expect(content.processStart == queue.last.processStart)

    try FileManager.default.removeItem(at: tickets.url(for: moved))
    let lease = try #require(tickets.acquireDisplayIfHead(moved))
    lease.release()
    #expect(queue.order() == [queue.last, queue.first, queue.middle].map(\.fileName))
  }

  @Test func aTicketWithoutAPlaceDecodesInArrivalOrder() throws {
    let json = Data(
      #"{"processStart":1,"summary":{"host":"claude","project":"p","tool":"Bash"}}"#.utf8)
    let content = try JSONDecoder().decode(TicketContent.self, from: json)
    #expect(content.menuPosition == nil)
    #expect(content.processStart == 1)
  }
}

private struct ThreeTickets {
  let temporary: TemporaryQueue
  let first: Ticket
  let middle: Ticket
  let last: Ticket

  init() throws {
    temporary = try TemporaryQueue()
    let own = getpid()
    let encoder = JSONEncoder()
    for timestamp: UInt64 in [100, 200, 300] {
      _ = try temporary.writeTicket(
        timestamp: timestamp, pid: own,
        content: encoder.encode(
          TicketContent(
            processStart: ProcessLiveness.startTime(of: own),
            summary: TicketSummary(
              host: .claude, project: "p\(timestamp)", tool: "Bash", agentType: nil))))
    }
    let live = temporary.queue.liveTickets()
    guard live.count == 3 else { throw ThreeTicketsMissing() }
    first = live[0]
    middle = live[1]
    last = live[2]
  }

  func order() -> [String] {
    temporary.queue.liveTickets().map(\.fileName)
  }
}

private struct ThreeTicketsMissing: Error {}
