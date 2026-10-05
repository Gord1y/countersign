import Darwin
import Foundation
import Testing

@testable import ApprovalCore

@Suite struct TicketQueueTests {
  @Test func enqueueWritesANamedTicketAtomically() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let nested = TicketQueue(
      directory: temporary.directory.appendingPathComponent("a/b/queue"),
      lockFile: temporary.lockFile
    )
    let summary = TicketSummary(
      host: .codex, project: "shop-api", tool: "apply_patch", agentType: "Explore")

    let before = clock_gettime_nsec_np(CLOCK_REALTIME)
    let ticket = try nested.enqueue(summary)
    let after = clock_gettime_nsec_np(CLOCK_REALTIME)

    #expect(ticket.pid == getpid())
    #expect(ticket.timestamp >= before && ticket.timestamp <= after)
    #expect(ticket.processStart != nil)
    #expect(ticket.processStart == ProcessLiveness.startTime(of: getpid()))
    #expect(ticket.summary == summary)
    #expect(ticket.fileName == Ticket.fileName(timestamp: ticket.timestamp, pid: getpid()))
    #expect(ticket.fileName.hasSuffix("-\(getpid()).json"))
    let paddedTimestamp = String(ticket.fileName.prefix(20))
    #expect(UInt64(paddedTimestamp) == ticket.timestamp)

    let names = try FileManager.default.contentsOfDirectory(atPath: nested.directory.path)
    #expect(names == [ticket.fileName])
    let data = try Data(contentsOf: nested.url(for: ticket))
    let content = try JSONDecoder().decode(TicketContent.self, from: data)
    #expect(content == TicketContent(processStart: ticket.processStart, summary: summary))
    #expect(nested.liveTickets() == [ticket])
  }

  @Test func fileNamesAreZeroPaddedAndParsedStrictly() {
    #expect(Ticket.fileName(timestamp: 42, pid: 7) == "00000000000000000042-7.json")
    #expect(
      Ticket.fileName(timestamp: UInt64.max, pid: 123) == "18446744073709551615-123.json")
    let parsed = Ticket.parseFileName("00000000000000000042-7.json")
    #expect(parsed?.timestamp == 42)
    #expect(parsed?.pid == 7)
    let rejected = [
      "42-7.json",
      "+0000000000000000042-7.json",
      "00000000000000000042--7.json",
      "00000000000000000042-+7.json",
      "00000000000000000042-0.json",
      "00000000000000000042-.json",
      "00000000000000000042-7-1.json",
      "00000000000000000042-99999999999.json",
      "00000000000000000042-7.json.tmp",
      ".00000000000000000042-7.json",
      "99999999999999999999-7.json",
      "display.lock",
    ]
    for name in rejected {
      #expect(Ticket.parseFileName(name) == nil, "\(name)")
    }
  }

  @Test func summaryIsBuiltFromTheRequest() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash-subagent"))
    #expect(
      TicketSummary(request: request)
        == TicketSummary(host: .claude, project: "shop-api", tool: "Bash", agentType: "Explore")
    )
  }

  @Test func ordersByTimestampThenPidAndCountsWaiters() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let own = getpid()
    let launchdStart = try #require(ProcessLiveness.startTime(of: 1))
    let dead = try ChildProcess.deadPid()

    let late = try temporary.writeTicket(timestamp: 300, pid: own, processStart: nil)
    let tiedHigh = try temporary.writeTicket(timestamp: 100, pid: own, processStart: nil)
    let tiedLow = try temporary.writeTicket(timestamp: 100, pid: 1, processStart: launchdStart)
    let first = try temporary.writeTicket(timestamp: 50, pid: own, processStart: nil)
    let deadName = try temporary.writeTicket(timestamp: 10, pid: dead, processStart: nil)

    let live = temporary.queue.liveTickets()
    #expect(live.map(\.fileName) == [first, tiedLow, tiedHigh, late])
    #expect(live.map(\.pid) == [own, 1, own, own])
    #expect(!temporary.fileExists(deadName))

    let head = try #require(live.first)
    let last = try #require(live.last)
    #expect(temporary.queue.isHead(head))
    #expect(!temporary.queue.isHead(last))
    #expect(temporary.queue.waitingCount(excluding: head) == 3)
    #expect(temporary.queue.waitingCount(excluding: last) == 3)
    let absent = Ticket(
      fileName: Ticket.fileName(timestamp: 1, pid: own), timestamp: 1, pid: own,
      processStart: nil, summary: nil)
    #expect(temporary.queue.waitingCount(excluding: absent) == 4)
    #expect(!temporary.queue.isHead(absent))
  }

  @Test func realRequestCountExcludesOnlyTestPanelSummariesAndOurs() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let own = getpid()
    let ownTicket = try temporary.queue.enqueue(.probe)
    let encoder = JSONEncoder()

    let realSummary = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: nil)
    _ = try temporary.writeTicket(
      timestamp: 100, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: realSummary)))
    #expect(temporary.queue.realRequestCount(excluding: ownTicket) == 1)

    let testSummary = TicketSummary(
      host: .claude, project: "Countersign test", tool: "Bash", agentType: nil,
      isTestPanel: true)
    _ = try temporary.writeTicket(
      timestamp: 200, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: testSummary)))
    #expect(temporary.queue.realRequestCount(excluding: ownTicket) == 1)

    _ = try temporary.writeTicket(
      timestamp: 300, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: nil)))
    #expect(temporary.queue.realRequestCount(excluding: ownTicket) == 2)
  }

  @Test func approvalCountSkipsTestPanelsCheckpointsAndOurs() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let own = getpid()
    let ownTicket = try temporary.queue.enqueue(.probe)
    let encoder = JSONEncoder()

    let approval = TicketSummary(host: .claude, project: "shop-api", tool: "Bash", agentType: nil)
    _ = try temporary.writeTicket(
      timestamp: 100, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: approval)))
    #expect(temporary.queue.approvalCount(excluding: ownTicket) == 1)

    let testPanel = TicketSummary(
      host: .claude, project: "Countersign test", tool: "Bash", agentType: nil, isTestPanel: true)
    _ = try temporary.writeTicket(
      timestamp: 200, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: testPanel)))
    let checkpoint = TicketSummary(
      host: .claude, project: "shop-api", tool: "Context checkpoint", agentType: nil,
      isContextCheckpoint: true)
    _ = try temporary.writeTicket(
      timestamp: 300, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: checkpoint)))
    #expect(temporary.queue.approvalCount(excluding: ownTicket) == 1)
    #expect(temporary.queue.approvalCount(excluding: nil) == 2)
  }

  @Test func aSummaryWithoutTheCheckpointFlagDecodesAsNotACheckpoint() throws {
    let json = Data(#"{"host":"claude","project":"p","tool":"Bash"}"#.utf8)
    let summary = try JSONDecoder().decode(TicketSummary.self, from: json)
    #expect(!summary.isContextCheckpoint)
  }

  @Test func aSummaryThatDoesNotAnswerInChatRoundTrips() throws {
    let summary = TicketSummary(
      host: .cursor, project: "shop-api", tool: "Shell", agentType: nil, answersInChat: false)
    let decoded = try JSONDecoder().decode(
      TicketSummary.self, from: JSONEncoder().encode(summary))
    #expect(decoded == summary)
    #expect(!decoded.answersInChat)
  }

  @Test func aSummaryWithoutTheChatFlagDecodesAsAnsweringInChat() throws {
    let json = Data(#"{"host":"cursor","project":"p","tool":"Shell"}"#.utf8)
    let summary = try JSONDecoder().decode(TicketSummary.self, from: json)
    #expect(summary.answersInChat)
  }

  @Test func aSummaryBuiltFromARequestAnswersInChatByDefault() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash-subagent"))
    #expect(TicketSummary(request: request).answersInChat)
    #expect(!TicketSummary(request: request, answersInChat: false).answersInChat)
  }

  @Test func aCheckpointRequestFillsTheSummaryFlag() {
    let input = ContextCheckpointInput(
      sessionID: "s", cwd: "/tmp/shop-api", transcriptPath: nil, permissionMode: nil)
    let prompt = ContextCheckpointPrompt(
      tokens: 1, level: .soft, ladder: [1, 2, 3], modelID: nil, handoffFile: "h.md",
      notes: .default)
    let summary = TicketSummary(request: .contextCheckpoint(input, prompt: prompt))
    #expect(summary.isContextCheckpoint)
    #expect(summary.tool == "Context checkpoint")
    #expect(summary.project == "shop-api")
  }

  @Test func waitingEntriesAreOldestFirstExcludingSelf() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let own = getpid()
    let firstSummary = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: nil)
    let secondSummary = TicketSummary(
      host: .codex, project: "other-api", tool: "apply_patch", agentType: "Explore",
      agentDescription: "Fix the tests")
    let encoder = JSONEncoder()

    let first = try temporary.writeTicket(
      timestamp: 100, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: firstSummary)))
    let second = try temporary.writeTicket(
      timestamp: 200, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: secondSummary)))
    let ownTicket = try temporary.queue.enqueue(.probe)

    #expect(
      temporary.queue.waitingEntries(excluding: ownTicket)
        == [
          WaitingEntry(summary: firstSummary, ticketID: Self.id(first)),
          WaitingEntry(summary: secondSummary, ticketID: Self.id(second)),
        ])
  }

  private static func id(_ fileName: String) -> String {
    String(fileName.dropLast(Ticket.fileSuffix.count))
  }

  @Test func waitingEntriesRepresentAnUnreadableSummaryAsUnknownRatherThanDroppingIt() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let own = getpid()
    let summary = TicketSummary(host: .claude, project: "shop-api", tool: "Bash", agentType: nil)

    let unreadable = try temporary.writeTicket(
      timestamp: 1, pid: own, content: Data("not json".utf8))
    let readable = try temporary.writeTicket(
      timestamp: 2, pid: own,
      content: JSONEncoder().encode(TicketContent(processStart: nil, summary: summary)))
    let ownTicket = try temporary.queue.enqueue(.probe)

    #expect(temporary.queue.waitingCount(excluding: ownTicket) == 2)
    #expect(
      temporary.queue.waitingEntries(excluding: ownTicket)
        == [
          WaitingEntry(summary: nil, ticketID: Self.id(unreadable)),
          WaitingEntry(summary: summary, ticketID: Self.id(readable)),
        ])
  }

  @Test func waitingEntriesWithoutExclusionListEveryLiveTicketOldestFirst() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let own = getpid()
    let dead = try ChildProcess.deadPid()
    let firstSummary = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: nil)
    let lastSummary = TicketSummary(
      host: .codex, project: "other-api", tool: "apply_patch", agentType: "Explore")
    let encoder = JSONEncoder()

    let last = try temporary.writeTicket(
      timestamp: 300, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: lastSummary)))
    let unreadable = try temporary.writeTicket(
      timestamp: 200, pid: own, content: Data("not json".utf8))
    let first = try temporary.writeTicket(
      timestamp: 100, pid: own,
      content: encoder.encode(TicketContent(processStart: nil, summary: firstSummary)))
    let deadName = try temporary.writeTicket(timestamp: 50, pid: dead, processStart: nil)
    let ownTicket = try temporary.queue.enqueue(.probe)

    #expect(
      temporary.queue.waitingEntries() == [
        WaitingEntry(summary: firstSummary, ticketID: Self.id(first)),
        WaitingEntry(summary: nil, ticketID: Self.id(unreadable)),
        WaitingEntry(summary: lastSummary, ticketID: Self.id(last)),
        WaitingEntry(summary: .probe, ticketID: ownTicket.id),
      ])
    #expect(temporary.queue.waitingEntries().count == temporary.queue.liveTickets().count)
    #expect(temporary.queue.waitingEntries(excluding: ownTicket).count == 3)
    #expect(!temporary.fileExists(deadName))
  }

  @Test func waitingEntriesWithoutExclusionAreEmptyForAnEmptyOrMissingQueue() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }

    #expect(temporary.queue.waitingEntries().isEmpty)
    temporary.remove()
    #expect(temporary.queue.waitingEntries().isEmpty)
  }

  @Test func agentLabelPrefersTheTaskDescriptionOverTheAgentType() {
    let described = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: "Explore",
      agentDescription: "Find the flaky test")
    let emptyDescription = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: "Explore",
      agentDescription: "")
    let typeOnly = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: "Explore")
    let notASubagent = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: nil,
      agentDescription: "Orphaned description")

    #expect(described.agentLabel == "Find the flaky test")
    #expect(emptyDescription.agentLabel == "Explore")
    #expect(typeOnly.agentLabel == "Explore")
    #expect(notASubagent.agentLabel == nil)
  }

  @Test func decodesATicketSummaryWrittenBeforeAgentDescriptionExisted() throws {
    let json = """
      {"host":"claude","project":"shop-api","tool":"Bash","agentType":"Explore"}
      """
    let summary = try JSONDecoder().decode(TicketSummary.self, from: Data(json.utf8))
    #expect(summary.agentType == "Explore")
    #expect(summary.agentDescription == nil)
  }

  @Test func decodesATicketSummaryWithoutIsTestPanelAsFalseAndRoundTripsTrue() throws {
    let json = """
      {"host":"claude","project":"shop-api","tool":"Bash","agentType":"Explore"}
      """
    let withoutKey = try JSONDecoder().decode(TicketSummary.self, from: Data(json.utf8))
    #expect(withoutKey.isTestPanel == false)

    let testPanelSummary = TicketSummary(
      host: .claude, project: "shop-api", tool: "Bash", agentType: "Explore", isTestPanel: true)
    let encoded = try JSONEncoder().encode(testPanelSummary)
    let decoded = try JSONDecoder().decode(TicketSummary.self, from: encoded)
    #expect(decoded.isTestPanel == true)
    #expect(decoded == testPanelSummary)
  }

  @Test func prunesATicketWhosePidWasReused() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let own = getpid()
    let start = try #require(ProcessLiveness.startTime(of: own))

    let reused = try temporary.writeTicket(timestamp: 1, pid: own, processStart: start + 1)
    let genuine = try temporary.writeTicket(timestamp: 2, pid: own, processStart: start)

    #expect(temporary.queue.liveTickets().map(\.fileName) == [genuine])
    #expect(!temporary.fileExists(reused))
    #expect(temporary.fileExists(genuine))
  }

  @Test func prunesTicketsOfDeadProcesses() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let dead = try ChildProcess.deadPid()

    let withStart = try temporary.writeTicket(timestamp: 1, pid: dead, processStart: 12_345)
    let garbage = try temporary.writeTicket(
      timestamp: 2, pid: dead, content: Data("garbage".utf8))

    #expect(temporary.queue.liveTickets().isEmpty)
    #expect(!temporary.fileExists(withStart))
    #expect(!temporary.fileExists(garbage))
    #expect(temporary.queue.liveTickets().isEmpty)
  }

  @Test func prunesAZombieTicketEvenWhenProcessStartMatches() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let pid = try ChildProcess.spawnInheritingDescriptors("/usr/bin/true", [])
    defer { ChildProcess.reap(pid) }

    let clock = SuspendingClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while !ChildProcess.isZombie(pid), clock.now < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    try #require(ChildProcess.isZombie(pid), "child did not become a zombie in time")

    let start = ProcessLiveness.startTime(of: pid)
    let ticketName = try temporary.writeTicket(timestamp: 1, pid: pid, processStart: start)

    #expect(temporary.queue.liveTickets().isEmpty)
    #expect(!temporary.fileExists(ticketName))
  }

  @Test func ignoresAndKeepsForeignFiles() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let dead = try ChildProcess.deadPid()
    let foreign = [
      ".hidden",
      ".\(Ticket.fileName(timestamp: 1, pid: dead))",
      ".\(Ticket.fileName(timestamp: 1, pid: getpid())).tmp",
      "leftover.tmp",
      "display.lock",
      "notes.txt",
      "README",
      "not-a-ticket.json",
      "\(Ticket.fileName(timestamp: 1, pid: dead)).bak",
    ]
    for name in foreign {
      try Data("x".utf8).write(to: temporary.directory.appendingPathComponent(name))
    }

    let ticket = try temporary.queue.enqueue(.probe)
    #expect(temporary.queue.liveTickets() == [ticket])
    #expect(temporary.queue.waitingCount(excluding: ticket) == 0)
    let lease = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    temporary.queue.remove(ticket)
    lease.release()
    #expect(temporary.queue.liveTickets().isEmpty)

    for name in foreign {
      #expect(temporary.fileExists(name), "\(name)")
    }
    #expect(!temporary.fileExists(ticket.fileName))
  }

  @Test func garbageContentForALiveProcessCountsAsLive() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let garbage = try temporary.writeTicket(
      timestamp: 5, pid: getpid(), content: Data("{not json".utf8))
    let empty = try temporary.writeTicket(timestamp: 6, pid: getpid(), content: nil)

    let live = temporary.queue.liveTickets()
    #expect(live.map(\.fileName) == [garbage, empty])
    #expect(live.allSatisfy { $0.processStart == nil && $0.summary == nil })
    #expect(temporary.fileExists(garbage))
    #expect(temporary.fileExists(empty))
  }

  @Test func restoresItsOwnVanishedTicketAndKeepsItsPlace() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ahead = try temporary.writeTicket(timestamp: 1, pid: 1, processStart: nil)
    let ticket = try temporary.queue.enqueue(.probe)
    let url = temporary.queue.url(for: ticket)
    let original = try Data(contentsOf: url)

    try FileManager.default.removeItem(at: url)
    #expect(temporary.queue.liveTickets().map(\.fileName) == [ahead])
    #expect(temporary.queue.acquireDisplayIfHead(ticket) == nil)
    #expect(try Data(contentsOf: url) == original)
    #expect(temporary.queue.liveTickets().map(\.fileName) == [ahead, ticket.fileName])

    try FileManager.default.removeItem(at: temporary.directory)
    let lease = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    #expect(try Data(contentsOf: url) == original)
    #expect(temporary.queue.liveTickets() == [ticket])
    lease.release()
  }

  @Test func neverRestoresAnotherProcesssTicket() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let foreign = Ticket(
      fileName: Ticket.fileName(timestamp: 1, pid: 1), timestamp: 1, pid: 1,
      processStart: nil, summary: .probe)

    #expect(temporary.queue.acquireDisplayIfHead(foreign) == nil)
    #expect(!temporary.fileExists(foreign.fileName))
  }

  @Test func onlyTheHeadGetsALease() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ahead = try temporary.writeTicket(timestamp: 1, pid: 1, processStart: nil)
    let ticket = try temporary.queue.enqueue(.probe)

    #expect(temporary.queue.acquireDisplayIfHead(ticket) == nil)
    try FileManager.default.removeItem(at: temporary.directory.appendingPathComponent(ahead))
    let lease = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    lease.release()
  }

  @Test func aSecondLeaseConflictsUntilTheFirstIsReleased() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)

    let first = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    #expect(temporary.queue.acquireDisplayIfHead(ticket) == nil)
    #expect(temporary.queue.acquireDisplayIfHead(ticket) == nil)
    first.release()

    let second = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    second.release()
    second.release()
    first.release()

    let third = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    third.release()
    #expect(FileManager.default.fileExists(atPath: temporary.lockFile.path))
  }

  @Test func droppingALeaseReleasesTheLock() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)

    func acquireThenDrop() -> Bool {
      let lease = temporary.queue.acquireDisplayIfHead(ticket)
      return withExtendedLifetime(lease) {
        lease != nil && temporary.queue.acquireDisplayIfHead(ticket) == nil
      }
    }

    #expect(acquireThenDrop())
    let again = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    again.release()
  }

  @Test func waitForDisplayStopsWhenAbandoned() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    try temporary.writeTicket(timestamp: 1, pid: 1, content: nil)
    let ticket = try temporary.queue.enqueue(.probe)

    var polls = 0
    let lease = temporary.queue.waitForDisplay(ticket, pollInterval: .milliseconds(1)) {
      polls += 1
      return polls > 3
    }
    #expect(lease == nil)
    #expect(polls == 4)
  }

  @Test func waitForDisplayReturnsALeaseOnceHead() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let ticket = try temporary.queue.enqueue(.probe)

    let lease = try #require(
      temporary.queue.waitForDisplay(ticket, pollInterval: .milliseconds(1)) { false })
    #expect(temporary.queue.acquireDisplayIfHead(ticket) == nil)
    lease.release()
  }

  @Test func leaseDescriptorIsNotInheritedBySpawnedChildren() throws {
    let temporary = try TemporaryQueue()
    defer { temporary.remove() }
    let lockSuffix = "\(temporary.directory.lastPathComponent)/display.lock"

    let inheritable = open(temporary.lockFile.path, O_RDWR | O_CREAT, 0o644)
    try #require(inheritable >= 0)
    let witness = try ChildProcess.spawnInheritingDescriptors("/bin/sleep", ["30"])
    let witnessPaths = ChildProcess.openVnodePaths(of: witness)
    ChildProcess.reap(witness)
    close(inheritable)
    #expect(witnessPaths.contains { $0.hasSuffix(lockSuffix) })

    let ticket = try temporary.queue.enqueue(.probe)
    let lease = try #require(temporary.queue.acquireDisplayIfHead(ticket))
    let child = try ChildProcess.spawnInheritingDescriptors("/bin/sleep", ["30"])
    let childPaths = ChildProcess.openVnodePaths(of: child)
    ChildProcess.reap(child)
    lease.release()
    #expect(!childPaths.contains { $0.hasSuffix(lockSuffix) })
  }
}

@Suite struct PauseSwitchTests {
  @Test func pausesAndResumes() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-pause-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("nested/paused")
    let pauseSwitch = PauseSwitch(file: file)

    #expect(!pauseSwitch.isPaused)
    try pauseSwitch.resume()
    #expect(!pauseSwitch.isPaused)

    try pauseSwitch.pause()
    #expect(pauseSwitch.isPaused)
    #expect(try Data(contentsOf: file).isEmpty)
    try pauseSwitch.pause()
    #expect(pauseSwitch.isPaused)

    try pauseSwitch.resume()
    #expect(!pauseSwitch.isPaused)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    try pauseSwitch.resume()
    #expect(!pauseSwitch.isPaused)
  }

  @Test func reportsWhetherThePauseLastsUntilTheAppOpens() throws {
    let (root, pauseSwitch) = Self.temporarySwitch()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(pauseSwitch.state == .active)
    #expect(try pauseSwitch.pauseUntilAppOpens())
    #expect(pauseSwitch.isPaused)
    #expect(pauseSwitch.state == .pausedUntilAppOpens)
    #expect(try Data(contentsOf: pauseSwitch.file) == PauseSwitch.untilAppOpensMarker)
    #expect(try pauseSwitch.pauseUntilAppOpens())
    #expect(pauseSwitch.state == .pausedUntilAppOpens)
  }

  @Test func aPauseUntilTheAppOpensLeavesAPlainPauseAsItIs() throws {
    let (root, pauseSwitch) = Self.temporarySwitch()
    defer { try? FileManager.default.removeItem(at: root) }

    try pauseSwitch.pause()
    #expect(try !pauseSwitch.pauseUntilAppOpens())
    #expect(pauseSwitch.state == .paused)
    #expect(try Data(contentsOf: pauseSwitch.file).isEmpty)
  }

  @Test func aPlainPauseReplacesAPauseUntilTheAppOpens() throws {
    let (root, pauseSwitch) = Self.temporarySwitch()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(try pauseSwitch.pauseUntilAppOpens())
    try pauseSwitch.pause()
    #expect(pauseSwitch.state == .paused)
    #expect(try Data(contentsOf: pauseSwitch.file).isEmpty)
  }

  @Test func resumeClearsAPauseUntilTheAppOpens() throws {
    let (root, pauseSwitch) = Self.temporarySwitch()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(try pauseSwitch.pauseUntilAppOpens())
    try pauseSwitch.resume()
    #expect(pauseSwitch.state == .active)
    #expect(!FileManager.default.fileExists(atPath: pauseSwitch.file.path))
  }

  @Test func anyOtherContentIsAPlainPause() throws {
    let (root, pauseSwitch) = Self.temporarySwitch()
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
      at: pauseSwitch.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("until Countersign opens".utf8).write(to: pauseSwitch.file)
    #expect(pauseSwitch.state == .paused)
    try Data("paused by hand\n".utf8).write(to: pauseSwitch.file)
    #expect(pauseSwitch.state == .paused)
  }

  @Test func launchResumesOnlyAPauseUntilTheAppOpens() throws {
    let (root, pauseSwitch) = Self.temporarySwitch()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(try !pauseSwitch.resumeIfPausedUntilAppOpens())
    #expect(pauseSwitch.state == .active)

    try pauseSwitch.pause()
    #expect(try !pauseSwitch.resumeIfPausedUntilAppOpens())
    #expect(pauseSwitch.state == .paused)

    try pauseSwitch.resume()
    #expect(try pauseSwitch.pauseUntilAppOpens())
    #expect(try pauseSwitch.resumeIfPausedUntilAppOpens())
    #expect(pauseSwitch.state == .active)
  }

  @Test func describesEachState() {
    #expect(PauseState.active.description == "active")
    #expect(PauseState.paused.description == "paused")
    #expect(PauseState.pausedUntilAppOpens.description == "paused until Countersign opens")
  }

  private static func temporarySwitch() -> (root: URL, pauseSwitch: PauseSwitch) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-pause-\(UUID().uuidString)")
    return (root, PauseSwitch(file: root.appendingPathComponent("nested/paused")))
  }
}
