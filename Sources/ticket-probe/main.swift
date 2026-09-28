import ApprovalCore
import Foundation
import os

func say(_ line: String) {
  try? FileHandle.standardOutput.write(contentsOf: Data("\(line)\n".utf8))
}

func uptime() -> TimeInterval {
  ProcessInfo.processInfo.systemUptime
}

let arguments = CommandLine.arguments
let isHold = arguments.count == 5 && arguments[1] == "hold"
let isChain = arguments.count == 5 && arguments[1] == "chain"
let isEnqueue = arguments.count == 4 && arguments[1] == "enqueue"
guard isHold || isChain || isEnqueue else {
  say(
    "usage: ticket-probe hold|chain <queueDir> <lockFile> <tag> | enqueue <queueDir> <lockFile>")
  exit(64)
}

signal(SIGPIPE, SIG_IGN)
let parent = getppid()
let queue = TicketQueue(
  directory: URL(fileURLWithPath: arguments[2]),
  lockFile: URL(fileURLWithPath: arguments[3])
)
let summary = TicketSummary(host: .claude, project: "probe", tool: "Bash", agentType: nil)

let ticket: Ticket
do {
  ticket = try queue.enqueue(summary)
} catch {
  exit(1)
}
queue.removeOnTermination(ticket)

func standBy(tag: String) -> (lease: DisplayLease, handedOff: Bool)? {
  let channel = QueueHandoffChannel(ticket: ticket)
  let handoff = OSAllocatedUnfairLock<QueueHandoff?>(initialState: nil)
  let listener = channel.listen(on: DispatchQueue(label: "ticket-probe.handoff")) { state in
    handoff.withLock { $0 = QueueHandoff(receivedAt: uptime(), state: state) }
    say("handed off \(tag) \(state)")
    channel.signalReady()
  }
  defer { listener?.cancel() }
  say("standby \(tag)")
  while getppid() == parent {
    if let lease = queue.acquireDisplayIfHead(ticket) {
      let handedOff = handoff.withLock { $0 }?.isFresh(at: uptime()) == true
      return (lease, handedOff)
    }
    Thread.sleep(forTimeInterval: 0.005)
  }
  return nil
}

let probeReadyTimeout: TimeInterval = 2

func handOff(tag: String) {
  guard let successor = queue.nextInLine(after: ticket) else { return }
  let channel = QueueHandoffChannel(ticket: successor)
  if let elapsed = channel.request(state: 7, timeout: probeReadyTimeout) {
    let micros =
      elapsed.components.seconds * 1_000_000 + elapsed.components.attoseconds / 1_000_000_000_000
    say("ready \(tag) \(micros)")
  } else {
    say("no reply \(tag)")
  }
}

if isHold {
  let tag = arguments[4]
  let lease = queue.waitForDisplay(ticket, pollInterval: .milliseconds(20)) {
    getppid() != parent
  }
  if let lease {
    say("displaying \(tag)")
    _ = readLine()
    queue.remove(ticket)
    lease.release()
    say("released \(tag)")
  } else {
    queue.remove(ticket)
  }
} else if isChain {
  let tag = arguments[4]
  let turn = queue.waitForTurn(ticket, pollInterval: 0.02) { getppid() != parent }
  let shown: (lease: DisplayLease, handedOff: Bool)?
  switch turn {
  case .display(let lease):
    shown = (lease, false)
  case .nextInLine:
    shown = standBy(tag: tag)
  case .abandoned:
    shown = nil
  }
  if let shown {
    say("showing \(tag) \(shown.handedOff ? "handoff" : "idle") \(Int64(uptime() * 1_000_000))")
    _ = readLine()
    say("finishing \(tag) \(Int64(uptime() * 1_000_000))")
    handOff(tag: tag)
    queue.remove(ticket)
    shown.lease.release()
    say("released \(tag)")
  } else {
    queue.remove(ticket)
  }
} else {
  say("queued \(ticket.fileName)")
  _ = readLine()
  queue.remove(ticket)
}
exit(0)
