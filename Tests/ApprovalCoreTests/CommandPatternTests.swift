import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ShellCommandSegmentsTests {
  @Test func splitsOnAndAnd() {
    #expect(ShellCommandSegments.split("cd x && pnpm lint")?.count == 2)
  }

  @Test func splitsOnEveryOperator() {
    #expect(ShellCommandSegments.split("a || b; c | d |& e & f") == ["a", "b", "c", "d", "e", "f"])
  }

  @Test func splitsOnNewlines() {
    #expect(ShellCommandSegments.split("ls\npwd") == ["ls", "pwd"])
  }

  @Test func quotedOperatorsStayInOneSegment() {
    #expect(ShellCommandSegments.split("echo 'a && b'")?.count == 1)
    #expect(ShellCommandSegments.split("echo \"a; b\"")?.count == 1)
    #expect(ShellCommandSegments.split("echo a\\;b")?.count == 1)
  }

  @Test func redirectionsAreNotSeparators() {
    #expect(ShellCommandSegments.split("ls 2>&1") == ["ls 2>&1"])
    #expect(ShellCommandSegments.split("ls >&2") == ["ls >&2"])
    #expect(ShellCommandSegments.split("ls &> out") == ["ls &> out"])
    #expect(ShellCommandSegments.split("ls &>> out") == ["ls &>> out"])
  }

  @Test func substitutionsAndGroupingsAreUnknown() {
    #expect(ShellCommandSegments.split("echo $(rm -rf x)") == nil)
    #expect(ShellCommandSegments.split("echo `id`") == nil)
    #expect(ShellCommandSegments.split("echo \"$(id)\"") == nil)
    #expect(ShellCommandSegments.split("diff <(ls) <(ls)") == nil)
    #expect(ShellCommandSegments.split("cat >(tee x)") == nil)
    #expect(ShellCommandSegments.split("(cd x && ls)") == nil)
  }

  @Test func singleQuotesHideSubstitutions() {
    #expect(ShellCommandSegments.split("echo '$(id)'")?.count == 1)
  }

  @Test func unclosedQuotesAreUnknown() {
    #expect(ShellCommandSegments.split("echo 'open") == nil)
    #expect(ShellCommandSegments.split("echo \"open") == nil)
  }

  @Test func emptyCommandsHaveNoSegments() {
    #expect(ShellCommandSegments.split("") == [])
    #expect(ShellCommandSegments.split("  ") == [])
  }
}

@Suite struct CommandPatternTests {
  @Test func plainPatternIsAPrefixOnWordBoundaries() {
    let git = CommandPattern("git")
    #expect(git.matches("git status"))
    #expect(git.matches("git"))
    #expect(!git.matches("gitk"))
    let gitStatus = CommandPattern("git status")
    #expect(gitStatus.matches("git status --short"))
    #expect(gitStatus.matches("git status"))
    #expect(!gitStatus.matches("git statusx"))
    #expect(!gitStatus.matches("git"))
  }

  @Test func argumentGlobMatchesTheWholeArguments() {
    let install = CommandPattern("npm:install*")
    #expect(install.matches("npm install"))
    #expect(install.matches("npm install express"))
    #expect(!install.matches("npm ci"))
    #expect(!install.matches("npmx install"))
    let anything = CommandPattern("git:*")
    #expect(anything.matches("git"))
    #expect(anything.matches("git push"))
    #expect(!anything.matches("gitk"))
  }

  @Test func argumentGlobWithoutAStarIsExact() {
    let exact = CommandPattern("npm:install")
    #expect(exact.matches("npm install"))
    #expect(!exact.matches("npm install express"))
  }

  @Test func emptyPatternMatchesNothing() {
    #expect(!CommandPattern("").matches("ls"))
    #expect(!CommandPattern("  ").matches("ls"))
    #expect(!CommandPattern("").matches(""))
  }

  @Test func matchingIsCaseSensitive() {
    #expect(!CommandPattern("Git").matches("git status"))
    #expect(!CommandPattern("git").matches("Git status"))
  }

  @Test func aTabSeparatesThePatternFromTheArguments() {
    #expect(CommandPattern("git").matches("git\tstatus"))
    #expect(CommandPattern("npm:install*").matches("npm\tinstall express"))
  }

  @Test func everySegmentMustMatch() {
    let patterns = ["cd", "pnpm lint"].map(CommandPattern.init)
    #expect(CommandPattern.allMatch("cd x && pnpm lint", patterns: patterns))
    #expect(!CommandPattern.allMatch("cd x && rm -rf y", patterns: patterns))
  }

  @Test func pipesNeedBothSidesOnTheList() {
    let lintOnly = [CommandPattern("pnpm lint")]
    #expect(!CommandPattern.allMatch("pnpm lint | tee out", patterns: lintOnly))
    let both = ["pnpm lint", "tee"].map(CommandPattern.init)
    #expect(CommandPattern.allMatch("pnpm lint | tee out", patterns: both))
  }

  @Test func unreadableAndEmptyCommandsNeverMatch() {
    let patterns = [CommandPattern("echo")]
    #expect(!CommandPattern.allMatch("echo $(id)", patterns: patterns))
    #expect(!CommandPattern.allMatch("", patterns: patterns))
  }
}

@Suite struct CursorAllowlistSkipTests {
  private func shellRequest() throws -> (request: ApprovalRequest, command: String) {
    let request = try CursorAdapter.parse(FixtureLoader.data("cursor-shell"))
    guard case .permission(let prompt) = request.kind,
      case .bash(let command, _) = prompt.body
    else {
      throw FixtureLoader.LoaderError.missing("cursor-shell command")
    }
    return (request, command)
  }

  private func environment(
    _ runMode: CursorRunMode, allowlist: [String]?
  ) -> CursorEnvironment {
    CursorEnvironment(
      runMode: runMode,
      commandAllowlist: allowlist.map {
        CursorCommandAllowlist(patterns: $0, source: .inApp)
      })
  }

  @Test func skipsInTheThreeModesThatHonourTheAllowlist() throws {
    let (request, command) = try shellRequest()
    let firstWord = String(command.prefix(while: { $0 != " " }))
    let expected: [CursorRunMode: Bool] = [
      .allowlist: true, .autoReview: true, .runEverything: true,
      .asksEveryTime: false, .unknown: false,
    ]
    for mode in CursorRunMode.allCases {
      let result = environment(mode, allowlist: [firstWord]).allowsWithoutAsking(request)
      #expect(result == expected[mode])
    }
  }

  @Test func aCommandOffTheListIsNotSkipped() throws {
    let (request, _) = try shellRequest()
    #expect(!environment(.allowlist, allowlist: ["ls"]).allowsWithoutAsking(request))
  }

  @Test func anUnreadableAllowlistIsNotSkipped() throws {
    let (request, _) = try shellRequest()
    #expect(!environment(.allowlist, allowlist: nil).allowsWithoutAsking(request))
  }

  @Test func mcpRequestsAreNeverSkipped() throws {
    let request = try CursorAdapter.parse(FixtureLoader.data("cursor-mcp-url"))
    #expect(!environment(.runEverything, allowlist: ["*", "mcp"]).allowsWithoutAsking(request))
  }

  @Test func claudeRequestsAreNeverSkipped() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash"))
    guard case .permission(let prompt) = request.kind, case .bash(let command, _) = prompt.body
    else {
      throw FixtureLoader.LoaderError.missing("claude-bash command")
    }
    let firstWord = String(command.prefix(while: { $0 != " " }))
    #expect(!environment(.allowlist, allowlist: [firstWord]).allowsWithoutAsking(request))
  }
}
