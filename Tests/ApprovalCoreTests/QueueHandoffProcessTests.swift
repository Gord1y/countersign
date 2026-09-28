import Darwin
import Foundation
import Testing

@testable import ApprovalCore

@Suite(.serialized) struct QueueHandoffProcessTests {
  private func launchInOrder(
    _ tags: [String],
    into temporary: TemporaryQueue,
    group: ProbeGroup
  ) async throws -> [ProbeProcess] {
    var launched: [ProbeProcess] = []
    for tag in tags {
      let probe = group.add(try ProbeProcess.chain(temporary, tag: tag))
      launched.append(probe)
      let expected = launched.map(\.pid)
      try #require(
        await eventually {
          temporary.queue.liveTickets().map(\.pid).suffix(expected.count) == expected[...]
        },
        "\(tag) did not enqueue behind \(launched.dropLast().map(\.tag))"
      )
      try await Task.sleep(for: .milliseconds(5))
    }
    return launched
  }

  private func ticket(of probe: ProbeProcess, in temporary: TemporaryQueue) throws -> Ticket {
    try #require(temporary.queue.liveTickets().first { $0.pid == probe.pid })
  }

  @Test func aFinishedHeadHandsOffToTheWarmNextInLine() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let probes = try await launchInOrder(["a", "b", "c"], into: temporary, group: group)
    let (a, b, c) = (probes[0], probes[1], probes[2])

    #expect(await eventually { a.line(startingWith: "showing a idle") != nil })
    #expect(await eventually { b.line(startingWith: "standby b") != nil })
    #expect(await holds(for: .milliseconds(300)) { c.line(startingWith: "standby c") == nil })

    a.sendLine()
    #expect(await eventually { a.hasReleased && !a.isRunning })
    _ = try #require(a.number(after: "ready a "))
    #expect(b.line(startingWith: "handed off b 7") != nil)
    #expect(await eventually { b.line(startingWith: "showing b handoff") != nil })
    #expect(await eventually { c.line(startingWith: "standby c") != nil })

    b.sendLine()
    #expect(await eventually { b.hasReleased && !b.isRunning })
    #expect(b.line(startingWith: "ready b ") != nil)
    #expect(await eventually { c.line(startingWith: "showing c handoff") != nil })

    c.sendLine()
    #expect(await eventually { c.hasReleased && !c.isRunning })
    #expect(c.line(startingWith: "ready c") == nil)
    #expect(c.line(startingWith: "no reply c") == nil)
    #expect(temporary.queue.liveTickets().isEmpty)
  }

  @Test func aHandoffIsFreshOnlyWhenTheLeaseFollowsIt() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let head = try temporary.queue.enqueue(.probe)
    let lease = try #require(temporary.queue.acquireDisplayIfHead(head))
    let next = group.add(try ProbeProcess.chain(temporary, tag: "n"))
    #expect(await eventually { next.line(startingWith: "standby n") != nil })

    let channel = QueueHandoffChannel(ticket: try ticket(of: next, in: temporary))
    #expect(channel.request(state: 0, timeout: 2) != nil)
    try await Task.sleep(for: .seconds(QueueHandoff.freshness + 0.2))
    temporary.queue.remove(head)
    lease.release()

    #expect(await eventually { next.line(startingWith: "showing n idle") != nil })
    #expect(next.line(startingWith: "showing n handoff") == nil)
    next.sendLine()
    #expect(await eventually { next.hasReleased && !next.isRunning })
  }

  @Test func onlyTheNextInLineAnswersAHandoff() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let head = try temporary.queue.enqueue(.probe)
    let lease = try #require(temporary.queue.acquireDisplayIfHead(head))
    defer { lease.release() }
    let probes = try await launchInOrder(["n", "w"], into: temporary, group: group)
    let (next, waiter) = (probes[0], probes[1])
    #expect(await eventually { next.line(startingWith: "standby n") != nil })

    let clock = ContinuousClock()
    let start = clock.now
    let waiterChannel = QueueHandoffChannel(ticket: try ticket(of: waiter, in: temporary))
    #expect(waiterChannel.request(state: 0, timeout: QueueHandoff.readyTimeout) == nil)
    #expect(clock.now - start >= .milliseconds(140))
    #expect(waiter.line(startingWith: "handed off") == nil)
  }

  @Test func aHeadWhoseSuccessorIsNotListeningExitsAfterTheCap() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let head = group.add(try ProbeProcess.chain(temporary, tag: "h"))
    #expect(await eventually { head.line(startingWith: "showing h idle") != nil })
    let cold = group.add(try ProbeProcess.hold(temporary, tag: "cold"))
    #expect(await eventually { temporary.queue.liveTickets().count == 2 })

    head.sendLine()
    #expect(await eventually { head.hasReleased && !head.isRunning })
    #expect(head.line(startingWith: "no reply h") != nil)
    #expect(await eventually { cold.isDisplaying })
    cold.sendLine()
    #expect(await eventually { cold.hasReleased && !cold.isRunning })
  }
}
