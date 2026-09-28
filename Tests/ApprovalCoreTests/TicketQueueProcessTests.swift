import Darwin
import Foundation
import Testing

@testable import ApprovalCore

@Suite(.serialized) struct TicketQueueProcessTests {
  private func launchInOrder(
    _ tags: [String],
    into temporary: TemporaryQueue,
    group: ProbeGroup
  ) async throws -> [ProbeProcess] {
    var launched: [ProbeProcess] = []
    for tag in tags {
      let probe = group.add(try ProbeProcess.hold(temporary, tag: tag))
      launched.append(probe)
      let expected = launched.map(\.pid)
      try #require(
        await eventually { temporary.queue.liveTickets().map(\.pid) == expected },
        "\(tag) did not enqueue behind \(launched.dropLast().map(\.tag))"
      )
      try await Task.sleep(for: .milliseconds(5))
    }
    return launched
  }

  private func release(_ probe: ProbeProcess) async {
    probe.sendLine()
    #expect(await eventually { probe.hasReleased && !probe.isRunning }, "\(probe.tag) release")
    #expect(probe.termination == .exited(0))
  }

  @Test func exactlyOneProbeDisplaysAndTheyTakeTurnsInEnqueueOrder() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let probes = try await launchInOrder(["a", "b", "c"], into: temporary, group: group)

    for (index, probe) in probes.enumerated() {
      let waiting = Array(probes.dropFirst(index + 1))
      #expect(await eventually { probe.isDisplaying }, "\(probe.tag) should display")
      #expect(
        await holds(for: .seconds(1)) { group.displaying.map(\.pid) == [probe.pid] },
        "\(probe.tag) should display alone"
      )
      #expect(waiting.allSatisfy { !$0.hasDisplayed })
      let ticket = try #require(temporary.queue.liveTickets().first { $0.pid == probe.pid })
      #expect(temporary.queue.isHead(ticket))
      #expect(temporary.queue.waitingCount(excluding: ticket) == waiting.count)
      await release(probe)
      #expect(!temporary.fileExists(ticket.fileName))
    }

    #expect(temporary.queue.liveTickets().isEmpty)
    #expect(FileManager.default.fileExists(atPath: temporary.lockFile.path))
  }

  @Test func simultaneousProbesNeverDisplayTogether() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    for index in 0..<4 {
      _ = group.add(try ProbeProcess.hold(temporary, tag: "p\(index)"))
    }

    var displayed: [Int32] = []
    for _ in 0..<4 {
      #expect(await eventually { group.displaying.count == 1 })
      #expect(await holds(for: .milliseconds(300)) { group.displaying.count == 1 })
      let current = try #require(group.displaying.first)
      displayed.append(current.pid)
      await release(current)
    }

    #expect(Set(displayed) == Set(group.probes.map(\.pid)))
    #expect(temporary.queue.liveTickets().isEmpty)
  }

  @Test func aKilledDisplayerHandsOverToTheNextProbe() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let probes = try await launchInOrder(["a", "b"], into: temporary, group: group)
    let displayer = probes[0]
    let next = probes[1]
    let displayerTicket = try #require(
      temporary.queue.liveTickets().first { $0.pid == displayer.pid })

    #expect(await eventually { displayer.isDisplaying })
    #expect(await holds(for: .milliseconds(500)) { !next.hasDisplayed })

    displayer.send(SIGKILL)
    #expect(await displayer.waitForExit())
    #expect(displayer.termination == .signaled(SIGKILL))
    #expect(await eventually { next.isDisplaying })
    #expect(!temporary.fileExists(displayerTicket.fileName))
    #expect(!temporary.queue.liveTickets().contains { $0.pid == displayer.pid })

    await release(next)
    #expect(temporary.queue.liveTickets().isEmpty)
  }

  @Test func aKilledWaiterIsPrunedAndDoesNotBlockTheQueue() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let probes = try await launchInOrder(["a", "b", "c"], into: temporary, group: group)
    let displayer = probes[0]
    let victim = probes[1]
    let survivor = probes[2]
    let victimTicket = try #require(temporary.queue.liveTickets().first { $0.pid == victim.pid })

    #expect(await eventually { displayer.isDisplaying })
    victim.send(SIGKILL)
    #expect(await victim.waitForExit())
    #expect(victim.termination == .signaled(SIGKILL))
    #expect(
      await eventually { !temporary.queue.liveTickets().contains { $0.pid == victim.pid } })
    #expect(!temporary.fileExists(victimTicket.fileName))
    #expect(temporary.queue.liveTickets().map(\.pid) == [displayer.pid, survivor.pid])

    await release(displayer)
    #expect(await eventually { survivor.isDisplaying })
    #expect(!victim.hasDisplayed)
    await release(survivor)
    #expect(temporary.queue.liveTickets().isEmpty)
  }

  @Test(arguments: [SIGTERM, SIGINT, SIGHUP])
  func aTerminationSignalRemovesTheTicketAndExitsCleanly(signalNumber: Int32) async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let probe = group.add(try ProbeProcess.enqueue(temporary))

    #expect(await eventually { !probe.output.lines.isEmpty })
    let line = try #require(probe.output.lines.first)
    #expect(line.hasPrefix("queued "))
    let name = String(line.dropFirst("queued ".count))
    #expect(Ticket.parseFileName(name)?.pid == probe.pid)
    #expect(temporary.fileExists(name))
    #expect(temporary.queue.liveTickets().map(\.fileName) == [name])

    probe.send(signalNumber)
    #expect(await probe.waitForExit())
    #expect(probe.termination == .exited(0))
    #expect(!temporary.fileExists(name))
    #expect(await eventually { probe.output.isClosed })
    #expect(probe.output.lines == [line])
    #expect(temporary.queue.liveTickets().isEmpty)
  }

  @Test func aProbeNeedsBothTheHeadAndTheLockAcrossProcesses() async throws {
    let temporary = try TemporaryQueue()
    let group = ProbeGroup()
    defer {
      group.forceStopAll()
      temporary.remove()
    }
    let ticket = try temporary.queue.enqueue(.probe)
    let probe = group.add(try ProbeProcess.hold(temporary, tag: "p"))

    #expect(
      await eventually { temporary.queue.liveTickets().map(\.pid) == [getpid(), probe.pid] })
    #expect(await holds(for: .seconds(1)) { !probe.hasDisplayed })
    let lease = try #require(temporary.queue.acquireDisplayIfHead(ticket))

    temporary.queue.remove(ticket)
    #expect(temporary.queue.liveTickets().map(\.pid) == [probe.pid])
    #expect(await holds(for: .seconds(1)) { !probe.hasDisplayed })

    lease.release()
    #expect(await eventually { probe.isDisplaying })
    #expect(DisplayLease.acquire(lockFile: temporary.lockFile) == nil)

    await release(probe)
    let after = try #require(DisplayLease.acquire(lockFile: temporary.lockFile))
    after.release()
  }
}
