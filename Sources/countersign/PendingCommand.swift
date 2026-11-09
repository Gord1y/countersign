import ApprovalCore

enum PendingCommand {
  static let usage = PendingCommandLine.usage

  static func run(_ arguments: [String]) {
    guard let command = PendingCommandLine.parse(arguments) else {
      CommandLineOutput.fail(usage)
    }
    let paths = AppPaths.standard
    let queue = TicketQueue(directory: paths.queueDirectory, lockFile: paths.displayLockFile)
    let entries = queue.waitingEntries()
    switch command {
    case .list:
      if entries.isEmpty {
        print(PendingCommandText.empty)
      } else {
        for entry in entries {
          print(PendingCommandText.line(for: entry))
        }
      }
    case .answer(let answer, let ticketID):
      switch PendingAnswerCheck.check(answer, ticketID: ticketID, entries: entries) {
      case .unknownTicket:
        CommandLineOutput.fail(PendingCommandText.unknownTicket)
      case .notOffered(let offered):
        CommandLineOutput.fail(PendingCommandText.notOffered(answer, offered: offered))
      case .send:
        do {
          guard try queue.sendMenuAnswer(answer, toTicketID: ticketID) else {
            CommandLineOutput.fail(PendingCommandText.unknownTicket)
          }
          print(PendingCommandText.sent(answer))
        } catch {
          CommandLineOutput.fail("error: \(error)")
        }
      }
    }
  }
}
