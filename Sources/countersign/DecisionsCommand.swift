import ApprovalCore

enum DecisionsCommand {
  static let usage = DecisionsCommandLine.usage

  static func run(_ arguments: [String]) {
    guard let command = DecisionsCommandLine.parse(arguments) else {
      CommandLineOutput.fail(usage)
    }
    let history = DecisionHistory(paths: AppPaths.standard)
    switch command {
    case .list(let limit):
      let entries = history.recent(limit: limit)
      if entries.isEmpty {
        print(DecisionsCommandLine.empty)
      } else {
        for entry in entries {
          print(CompanionMenu.decisionRowTitle(for: entry))
        }
      }
    case .clear:
      do {
        try history.clear()
        print(DecisionsCommandLine.cleared)
      } catch {
        CommandLineOutput.fail("error: \(error)")
      }
    }
  }
}
