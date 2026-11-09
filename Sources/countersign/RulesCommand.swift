import ApprovalCore

enum RulesCommand {
  static let usage = RulesCommandLine.usage

  static func run(_ arguments: [String]) {
    guard let command = RulesCommandLine.parse(arguments) else {
      CommandLineOutput.fail(usage)
    }
    let paths = AppPaths.standard
    CommandLineOutput.failOnUnusableConfig(paths: paths)
    let loaded = ConfigFileLoader.load(paths: paths)
    let rules = loaded.file.rules ?? []
    switch command {
    case .list:
      if rules.isEmpty {
        print(RulesCommandLine.empty)
      } else {
        for (index, rule) in rules.enumerated() {
          print(RulesCommandLine.row(index: index, rule: rule))
        }
      }
      let unreadable = ApprovalRule.unreadableCount(in: loaded.logLines)
      if unreadable > 0 {
        print(RulesCommandLine.unreadableNotice(count: unreadable))
      }
    case .deny(let draft):
      if RulesCommandLine.needsScope(draft) {
        CommandLineOutput.fail(RulesCommandLine.noScope)
      }
      if !draft.problems.isEmpty {
        CommandLineOutput.fail("error: " + draft.problems.joined(separator: " "))
      }
      guard let rule = RulesCommandLine.denyRule(draft) else {
        CommandLineOutput.fail(usage)
      }
      if rules.contains(rule) {
        print(RulesCommandLine.alreadyThere(rule))
        return
      }
      do {
        try RuleFileWriter.add([rule], configFile: paths.configFile)
      } catch {
        CommandLineOutput.fail("error: \(SetupRun.describe(error))")
      }
      print(RulesCommandLine.added(rule))
    }
  }
}
