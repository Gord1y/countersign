import ApprovalCore
import Foundation

enum TestPanelCommand {
  static let usage = "usage: countersign test-panel [command|question|plan|context]"

  @MainActor
  static func run(_ arguments: [String]) -> Never {
    guard let kind = TestPanelKind.parse(arguments) else { CommandLineOutput.fail(usage) }
    let startedAt = ContinuousClock.now
    let paths = AppPaths.standard
    let log = EventLog(file: paths.logFile)
    log.rotateIfNeeded()
    let (configFile, configLogLines) = ConfigFileLoader.load(
      paths: paths, soundNames: SystemSounds.installedNames)
    for line in configLogLines {
      log.write("config: \(line)")
    }
    let settings = Settings.resolve(file: configFile, host: .claude)
    let request: ApprovalRequest
    do {
      request = try TestPanelSample.request(for: kind, settings: settings.contextCheckpoints)
    } catch {
      CommandLineOutput.fail("error: could not build the \(kind.rawValue) test panel")
    }
    log.write(TestPanelLog.start(kind))

    HookRunner.showPanel(
      for: request, mode: .test(kind), settings: settings, paths: paths, log: log,
      startedAt: startedAt, hostApp: nil)
  }

  static func takeDisplay(queue: TicketQueue, ticket: Ticket, log: EventLog) -> QueueTurn {
    let others = queue.liveTickets().filter { $0.fileName != ticket.fileName }
    let panelOnScreen = others.contains { QueueHandoffChannel(ticket: $0).shownDisplayID() != nil }
    switch TestPanelAdmission.decide(panelOnScreen: panelOnScreen, otherTickets: others.count) {
    case .refuse(let refusal):
      refuse(refusal, queue: queue, ticket: ticket, log: log)
    case .show:
      guard let lease = queue.acquireDisplayIfHead(ticket) else {
        refuse(.panelOnScreen, queue: queue, ticket: ticket, log: log)
      }
      return .display(lease)
    }
  }

  private static func refuse(
    _ refusal: TestPanelRefusal, queue: TicketQueue, ticket: Ticket, log: EventLog
  ) -> Never {
    queue.remove(ticket)
    log.write(TestPanelLog.refused(refusal))
    CommandLineOutput.fail("countersign: \(refusal.message)")
  }
}
