import Dispatch
import Foundation
import Testing
import os

@testable import ApprovalCore

@Suite struct QueueHandoffTests {
  private func ticket(timestamp: UInt64, pid: Int32) -> Ticket {
    Ticket(
      fileName: Ticket.fileName(timestamp: timestamp, pid: pid), timestamp: timestamp, pid: pid,
      processStart: nil, summary: nil)
  }

  private func uniqueTicket() -> Ticket {
    ticket(
      timestamp: clock_gettime_nsec_np(CLOCK_REALTIME), pid: Int32.random(in: 100_000...999_999))
  }

  @Test func placeNamesTheHeadTheNextInLineAndTheRest() {
    let first = ticket(timestamp: 1, pid: 10)
    let second = ticket(timestamp: 2, pid: 20)
    let third = ticket(timestamp: 3, pid: 30)
    let fourth = ticket(timestamp: 4, pid: 40)
    let live = [first, second, third, fourth]

    #expect(QueuePlace(of: first, among: live) == .head)
    #expect(QueuePlace(of: second, among: live) == .nextInLine)
    #expect(QueuePlace(of: third, among: live) == .behind)
    #expect(QueuePlace(of: fourth, among: live) == .behind)
    #expect(QueuePlace(of: ticket(timestamp: 5, pid: 50), among: live) == .absent)
    #expect(QueuePlace(of: first, among: []) == .absent)
  }

  @Test func successorIsTheTicketRightAfterTheGivenOne() {
    let first = ticket(timestamp: 1, pid: 10)
    let second = ticket(timestamp: 2, pid: 20)
    let third = ticket(timestamp: 3, pid: 30)
    let live = [first, second, third]

    #expect(QueuePlace.successor(of: first, among: live) == second)
    #expect(QueuePlace.successor(of: second, among: live) == third)
    #expect(QueuePlace.successor(of: third, among: live) == nil)
    #expect(QueuePlace.successor(of: ticket(timestamp: 9, pid: 90), among: live) == nil)
  }

  @Test func predecessorIsTheTicketRightBeforeTheGivenOne() {
    let first = ticket(timestamp: 1, pid: 10)
    let second = ticket(timestamp: 2, pid: 20)
    let third = ticket(timestamp: 3, pid: 30)
    let live = [first, second, third]

    #expect(QueuePlace.predecessor(of: first, among: live) == nil)
    #expect(QueuePlace.predecessor(of: second, among: live) == first)
    #expect(QueuePlace.predecessor(of: third, among: live) == second)
    #expect(QueuePlace.predecessor(of: ticket(timestamp: 9, pid: 90), among: live) == nil)
  }

  @Test func placeAndNextInLineReadTheLiveQueue() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let head = try temporary.queue.enqueue(.probe)
    let dead = try ChildProcess.deadPid()
    _ = try temporary.writeTicket(timestamp: head.timestamp + 1, pid: dead, processStart: nil)

    #expect(temporary.queue.place(of: head) == .head)
    #expect(temporary.queue.nextInLine(after: head) == nil)
    #expect(temporary.queue.ticketAhead(of: head) == nil)
  }

  @Test func ticketAheadSkipsDeadTickets() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let dead = try ChildProcess.deadPid()
    _ = try temporary.writeTicket(timestamp: 1, pid: dead, processStart: nil)
    let live = try temporary.queue.enqueue(.probe)
    _ = try temporary.writeTicket(timestamp: live.timestamp + 1, pid: getpid(), processStart: nil)
    let behind = ticket(timestamp: live.timestamp + 1, pid: getpid())

    #expect(temporary.queue.ticketAhead(of: live) == nil)
    #expect(temporary.queue.ticketAhead(of: behind)?.fileName == live.fileName)
  }

  @Test func waitForTurnReturnsTheDisplayToTheHead() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let head = try temporary.queue.enqueue(.probe)

    guard
      case .display(let lease) = temporary.queue.waitForTurn(
        head, pollInterval: 0.01, shouldAbandon: { false })
    else {
      Issue.record("the head should get the display")
      return
    }
    #expect(DisplayLease.acquire(lockFile: temporary.lockFile) == nil)
    lease.release()
  }

  @Test func waitForTurnStopsWhenAbandoned() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let head = try temporary.queue.enqueue(.probe)
    let lease = try #require(temporary.queue.acquireDisplayIfHead(head))
    defer { lease.release() }
    let other = uniqueTicket()

    guard
      case .abandoned = temporary.queue.waitForTurn(
        other, pollInterval: 0.01, shouldAbandon: { true })
    else {
      Issue.record("an abandoned wait should say so")
      return
    }
  }

  @Test func stateCarriesTheDisplayID() {
    #expect(QueueHandoff.state(displayID: 69_733_632) == 69_733_632)
    #expect(QueueHandoff.state(displayID: nil) == 0)
    #expect(QueueHandoff(receivedAt: 0, state: 69_733_632).displayID == 69_733_632)
    #expect(QueueHandoff(receivedAt: 0, state: 0).displayID == nil)
    #expect(QueueHandoff(receivedAt: 0, state: UInt64(UInt32.max) + 1).displayID == nil)
    #expect(QueueHandoff(receivedAt: 0, state: UInt64(UInt32.max)).displayID == UInt32.max)
  }

  @Test func aDisplayIDReadsBackFromItsState() {
    #expect(QueueHandoff.displayID(state: QueueHandoff.state(displayID: 7)) == 7)
    #expect(QueueHandoff.displayID(state: QueueHandoff.state(displayID: nil)) == nil)
    #expect(QueueHandoff.displayID(state: UInt64(UInt32.max) + 1) == nil)
  }

  @Test func aPreparingSuccessorGetsTheLongerReadyCap() {
    #expect(QueueHandoff.readyTimeout(successorPreparing: false) == QueueHandoff.readyTimeout)
    #expect(QueueHandoff.readyTimeout(successorPreparing: false) == 0.15)
    #expect(QueueHandoff.readyTimeout(successorPreparing: true) == 0.6)
    #expect(
      QueueHandoff.readyTimeout(successorPreparing: true) == QueueHandoff.preparingReadyTimeout)
  }

  @Test func aHandoffIsFreshForOneSecondAfterItArrives() {
    let handoff = QueueHandoff(receivedAt: 100, state: 0)
    #expect(handoff.isFresh(at: 100))
    #expect(handoff.isFresh(at: 100 + QueueHandoff.freshness))
    #expect(!handoff.isFresh(at: 100 + QueueHandoff.freshness + 0.001))
    #expect(!handoff.isFresh(at: 99.9))
  }

  @Test func aPreparedPanelOnTheHandoffsDisplayIsReused() {
    #expect(
      PreparedPanelReuse.decide(
        preparedDisplayID: 1, targetDisplayID: 1, screensChanged: false,
        fileContextChanged: { false }) == .reuse)
  }

  @Test func withNothingPreparedThePanelIsRebuiltWithoutReadingTheFile() {
    var fileChecks = 0
    let decision = PreparedPanelReuse.decide(
      preparedDisplayID: nil, targetDisplayID: 1, screensChanged: true,
      fileContextChanged: {
        fileChecks += 1
        return true
      })
    #expect(decision == .rebuild(.notPrepared))
    #expect(fileChecks == 0)
    #expect(
      PreparedPanelReuse.decide(
        preparedDisplayID: nil, targetDisplayID: nil, screensChanged: false,
        fileContextChanged: { false }) == .rebuild(.notPrepared))
  }

  @Test func changedScreensRebuildBeforeTheDisplayOrTheFileIsCompared() {
    var fileChecks = 0
    let decision = PreparedPanelReuse.decide(
      preparedDisplayID: 1, targetDisplayID: 2, screensChanged: true,
      fileContextChanged: {
        fileChecks += 1
        return true
      })
    #expect(decision == .rebuild(.screensChanged))
    #expect(fileChecks == 0)
  }

  @Test func anotherDisplayRebuildsWithoutReadingTheFile() {
    var fileChecks = 0
    let decision = PreparedPanelReuse.decide(
      preparedDisplayID: 1, targetDisplayID: 2, screensChanged: false,
      fileContextChanged: {
        fileChecks += 1
        return true
      })
    #expect(decision == .rebuild(.displayChanged))
    #expect(fileChecks == 0)
    #expect(
      PreparedPanelReuse.decide(
        preparedDisplayID: 1, targetDisplayID: nil, screensChanged: false,
        fileContextChanged: { false }) == .rebuild(.displayChanged))
  }

  @Test func aChangedFileRebuildsOnlyOnceEverythingElseMatches() {
    var fileChecks = 0
    let decision = PreparedPanelReuse.decide(
      preparedDisplayID: 1, targetDisplayID: 1, screensChanged: false,
      fileContextChanged: {
        fileChecks += 1
        return true
      })
    #expect(decision == .rebuild(.fileChanged))
    #expect(fileChecks == 1)
  }

  @Test func rebuildReasonsReadAsTheyAreLogged() {
    #expect(PreparedPanelReuse.RebuildReason.notPrepared.rawValue == "not prepared")
    #expect(PreparedPanelReuse.RebuildReason.screensChanged.rawValue == "screens changed")
    #expect(PreparedPanelReuse.RebuildReason.displayChanged.rawValue == "display changed")
    #expect(PreparedPanelReuse.RebuildReason.fileChanged.rawValue == "file changed")
  }

  @Test func namesAreScopedToTheTicket() {
    let first = ticket(timestamp: 1_234, pid: 56)
    let channel = QueueHandoffChannel(ticket: first)
    #expect(channel.requestName == "Countersign.handoff.00000000000000001234-56")
    #expect(channel.readyName == "Countersign.ready.00000000000000001234-56")
    #expect(channel.preparingName == "Countersign.preparing.00000000000000001234-56")
    #expect(channel.displayName == "Countersign.display.00000000000000001234-56")
    #expect(QueueHandoffChannel(ticket: ticket(timestamp: 1_234, pid: 57)) != channel)
  }

  @Test func aPreparationIsVisibleToAnotherReaderUntilItEnds() throws {
    let ticket = uniqueTicket()
    let reader = QueueHandoffChannel(ticket: ticket)
    #expect(!reader.isPreparing())

    let preparation = try #require(QueueHandoffChannel(ticket: ticket).publishPreparation())
    #expect(!reader.isPreparing())
    preparation.begin()
    #expect(reader.isPreparing())
    preparation.end()
    #expect(!reader.isPreparing())
    preparation.begin()
    #expect(!QueueHandoffChannel(ticket: uniqueTicket()).isPreparing())
    preparation.cancel()
    preparation.cancel()
    #expect(!reader.isPreparing())
    preparation.begin()
    #expect(!reader.isPreparing())
  }

  @Test func aShownDisplayIsVisibleToAnotherReaderUntilCleared() throws {
    let ticket = uniqueTicket()
    let reader = QueueHandoffChannel(ticket: ticket)
    #expect(reader.shownDisplayID() == nil)

    let shown = try #require(QueueHandoffChannel(ticket: ticket).publishShownDisplay())
    #expect(reader.shownDisplayID() == nil)
    shown.publish(displayID: 69_733_632)
    #expect(reader.shownDisplayID() == 69_733_632)
    shown.publish(displayID: 2)
    #expect(reader.shownDisplayID() == 2)
    shown.clear()
    #expect(reader.shownDisplayID() == nil)
    shown.publish(displayID: 3)
    #expect(QueueHandoffChannel(ticket: uniqueTicket()).shownDisplayID() == nil)
    shown.cancel()
    shown.cancel()
    #expect(reader.shownDisplayID() == nil)
    shown.publish(displayID: 4)
    #expect(reader.shownDisplayID() == nil)
  }

  @Test func aRegistrationReadsNothingOnceCancelled() throws {
    let registration = try #require(NotifyRegistration(name: "Countersign.test.\(UUID())"))
    registration.setState(9)
    #expect(registration.state() == 9)
    registration.cancel()
    #expect(registration.state() == nil)
  }

  @Test func aPromptReplyArrivesWithoutWaitingForPreparation() throws {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let listener = try #require(
      channel.listen(on: DispatchQueue(label: "QueueHandoffTests.prompt")) { _ in
        channel.signalReady()
      })
    defer { listener.cancel() }

    let reply = channel.request(state: 1, timeout: { _ in 10 }, isPreparing: { false })
    #expect(reply.elapsed != nil)
    #expect(!reply.waitedForPreparation)
  }

  @Test func withNoReplyAndNoPreparationTheShortCapApplies() {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let isPreparingCalls = OSAllocatedUnfairLock<Int>(initialState: 0)
    let clock = ContinuousClock()
    let start = clock.now
    let reply = channel.request(
      state: 1,
      timeout: { preparing in preparing ? 10 : 0.05 },
      isPreparing: {
        isPreparingCalls.withLock { $0 += 1 }
        return false
      })
    let waited = clock.now - start

    #expect(reply == QueueHandoffReply(elapsed: nil, waitedForPreparation: false))
    #expect(waited >= .milliseconds(45))
    #expect(waited < .seconds(5))
    #expect(isPreparingCalls.withLock { $0 } == 2)
  }

  @Test func aSuccessorPreparingBeforeTheRequestGetsTheLongerCap() throws {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let listener = try #require(
      channel.listen(on: DispatchQueue(label: "QueueHandoffTests.preparedEarly")) { _ in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
          channel.signalReady()
        }
      })
    defer { listener.cancel() }

    let reply = channel.request(
      state: 1, timeout: { preparing in preparing ? 10 : 0.05 }, isPreparing: { true })
    let elapsed = try #require(reply.elapsed)
    #expect(reply.waitedForPreparation)
    #expect(elapsed >= .milliseconds(190))
  }

  @Test func aSuccessorThatStartsPreparingAfterTheRequestStillGetsTheLongerCap() throws {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let isPreparingCalls = OSAllocatedUnfairLock<Int>(initialState: 0)
    let listener = try #require(
      channel.listen(on: DispatchQueue(label: "QueueHandoffTests.preparedLate")) { _ in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
          channel.signalReady()
        }
      })
    defer { listener.cancel() }

    let reply = channel.request(
      state: 1,
      timeout: { preparing in preparing ? 10 : 0.05 },
      isPreparing: {
        isPreparingCalls.withLock { calls in
          calls += 1
          return calls > 1
        }
      })
    let elapsed = try #require(reply.elapsed)
    #expect(reply.waitedForPreparation)
    #expect(elapsed >= .milliseconds(190))
    #expect(isPreparingCalls.withLock { $0 } == 2)
  }

  @Test func aSuccessorStillPreparingPastTheLongerCapGetsNoReply() throws {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let preparation = try #require(channel.publishPreparation())
    defer { preparation.cancel() }
    preparation.begin()
    let clock = ContinuousClock()
    let start = clock.now
    let reply = channel.request(state: 1)
    let waited = clock.now - start

    #expect(reply == QueueHandoffReply(elapsed: nil, waitedForPreparation: true))
    #expect(waited >= .milliseconds(590))
  }

  @Test func aRequestReachesTheListenerWithItsStateAndGetsTheReadySignal() async throws {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let received = OSAllocatedUnfairLock<[UInt64]>(initialState: [])
    let listener = try #require(
      channel.listen(on: DispatchQueue(label: "QueueHandoffTests.listener")) { state in
        received.withLock { $0.append(state) }
        channel.signalReady()
      })
    defer { listener.cancel() }

    let elapsed = try #require(channel.request(state: 42, timeout: 2))
    #expect(elapsed < .seconds(2))
    #expect(received.withLock { $0 } == [42])
  }

  @Test func aRequestWithNoListenerTimesOut() {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let clock = ContinuousClock()
    let start = clock.now
    #expect(channel.request(state: 1, timeout: 0.05) == nil)
    #expect(clock.now - start >= .milliseconds(45))
  }

  @Test func aListenerIgnoresRequestsForOtherTickets() async {
    let mine = QueueHandoffChannel(ticket: uniqueTicket())
    let other = QueueHandoffChannel(ticket: uniqueTicket())
    let received = OSAllocatedUnfairLock(initialState: false)
    let listener = mine.listen(on: DispatchQueue(label: "QueueHandoffTests.other")) { _ in
      received.withLock { $0 = true }
      mine.signalReady()
    }
    defer { listener?.cancel() }

    #expect(other.request(state: 1, timeout: 0.05) == nil)
    #expect(!received.withLock { $0 })
  }

  @Test func aCancelledListenerNoLongerAnswers() {
    let channel = QueueHandoffChannel(ticket: uniqueTicket())
    let listener = channel.listen(on: DispatchQueue(label: "QueueHandoffTests.cancel")) { _ in
      channel.signalReady()
    }
    listener?.cancel()
    listener?.cancel()

    #expect(channel.request(state: 1, timeout: 0.05) == nil)
  }
}
