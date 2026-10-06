import Darwin
import Foundation
import Testing

@testable import ApprovalCore

@Suite struct TicketParkingTests {
  @Test func parkingTheHeadMakesTheNextTicketTheHead() throws {
    let queue = try ParkableTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let parked = try tickets.park(queue.first)

    #expect(parked.isParked)
    #expect(!tickets.isHead(parked))
    #expect(tickets.isHead(queue.middle))
    #expect(tickets.acquireDisplayIfHead(parked) == nil)
    let lease = try #require(tickets.acquireDisplayIfHead(queue.middle))
    lease.release()
  }

  @Test func aParkedTicketStaysWaitingButIsNotAContender() throws {
    let queue = try ParkableTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let parked = try tickets.park(queue.middle)

    #expect(tickets.liveTickets().contains(parked))
    #expect(tickets.waitingEntries(excluding: queue.first).contains { $0.ticketID == parked.id })
    #expect(tickets.waitingEntries().contains { $0.ticketID == parked.id })
    #expect(tickets.waitingCount(excluding: queue.first) == 2)
    #expect(tickets.realRequestCount(excluding: queue.first) == 1)
    #expect(tickets.approvalCount(excluding: queue.first) == 1)
  }

  @Test func theQueueQueriesSkipAParkedTicketInTheMiddle() throws {
    let queue = try ParkableTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let parked = try tickets.park(queue.middle)

    #expect(tickets.nextInLine(after: queue.first)?.fileName == queue.last.fileName)
    #expect(tickets.ticketAhead(of: queue.last)?.fileName == queue.first.fileName)
    #expect(tickets.place(of: queue.last) == .nextInLine)
    #expect(tickets.place(of: parked) == .absent)
  }

  @Test func aParkedTicketAtTheFrontDoesNotOvertakeFromTheMenu() throws {
    let queue = try ParkableTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let shown = try tickets.showNow(queue.last, isOnScreen: { _ in false }).ticket
    #expect(tickets.isOvertakenFromMenu(queue.first))

    _ = try tickets.park(shown)

    #expect(!tickets.isOvertakenFromMenu(queue.first))
  }

  @Test func showNowUnparksAndReturnsTheTicketToTheHead() throws {
    let queue = try ParkableTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let parked = try tickets.park(queue.first)
    #expect(!tickets.isHead(parked))

    let result = try tickets.showNow(parked, isOnScreen: { _ in false })

    #expect(!result.ticket.isParked)
    #expect(result.place == .front)
    #expect(tickets.liveTickets().first == result.ticket)
    #expect(tickets.isHead(result.ticket))
    let content = try storedContent(of: result.ticket, in: tickets)
    #expect(content.parked == nil)
  }

  @Test func aTicketWrittenWithoutTheFieldReadsAsNotParked() throws {
    let queue = try ParkableTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    #expect(tickets.liveTickets().allSatisfy { !$0.isParked })
    let content = try storedContent(of: queue.first, in: tickets)
    #expect(content.parked == nil)
  }

  @Test func anUnparkedTicketFileHasNoParkedKeyAndAParkedOneRoundTrips() throws {
    let queue = try ParkableTickets()
    defer { queue.temporary.remove() }
    let tickets = queue.temporary.queue

    let unparkedText = String(
      decoding: try Data(contentsOf: tickets.url(for: queue.first)), as: UTF8.self)
    #expect(!unparkedText.contains("parked"))

    let parked = try tickets.park(queue.first)
    let parkedText = String(
      decoding: try Data(contentsOf: tickets.url(for: parked)), as: UTF8.self)
    #expect(parkedText.contains("\"parked\":true"))
    #expect(try storedContent(of: parked, in: tickets).parked == true)
    #expect(tickets.liveTickets().first { $0.fileName == parked.fileName } == parked)
  }

  private func storedContent(of ticket: Ticket, in tickets: TicketQueue) throws -> TicketContent {
    try JSONDecoder().decode(
      TicketContent.self, from: Data(contentsOf: tickets.url(for: ticket)))
  }
}

private struct ParkableTickets {
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
    guard live.count == 3 else { throw ParkableTicketsMissing() }
    first = live[0]
    middle = live[1]
    last = live[2]
  }
}

private struct ParkableTicketsMissing: Error {}
