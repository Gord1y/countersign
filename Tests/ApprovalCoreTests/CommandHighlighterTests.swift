import Foundation
import Testing

@testable import ApprovalCore

private func text(_ token: ShellToken, in command: String) -> String {
  String(command[token.range])
}

@Suite struct CommandHighlighterTests {
  @Test func highlightsClaudeBashFixtureCommand() throws {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash"))
    guard case .permission(let prompt) = request.kind, case .bash(let command, _) = prompt.body
    else {
      Issue.record("expected bash body")
      return
    }
    let tokens = CommandHighlighter.tokens(in: command)
    let described = tokens.map { ($0.kind, text($0, in: command)) }
    #expect(
      described.map(\.0) == [.command, .flag, .operator, .command, .string])
    #expect(
      described.map(\.1) == [
        "git", "--force-with-lease", "&&", "echo", "\"done $HOME\"",
      ])
  }

  @Test func highlightsSingleQuotedStringsWithoutEscapesOrVariables() {
    let command = "echo 'raw $HOME \\n text'"
    let tokens = CommandHighlighter.tokens(in: command)
    #expect(tokens.map(\.kind) == [.command, .string])
    #expect(text(tokens[1], in: command) == "'raw $HOME \\n text'")
  }

  @Test func highlightsDoubleQuotedStringsWithEscapesAsOneToken() {
    let command = "echo \"say \\\"hi\\\" $USER\""
    let tokens = CommandHighlighter.tokens(in: command)
    #expect(tokens.map(\.kind) == [.command, .string])
    #expect(text(tokens[1], in: command) == "\"say \\\"hi\\\" $USER\"")
  }

  @Test func highlightsUnterminatedStringToEndOfInput() {
    let command = "echo 'unterminated"
    let tokens = CommandHighlighter.tokens(in: command)
    #expect(tokens.map(\.kind) == [.command, .string])
    #expect(text(tokens[1], in: command) == "'unterminated")
  }

  @Test func highlightsVariableForms() {
    let command = "echo $HOME ${PATH} $1 $@ $? $$"
    let tokens = CommandHighlighter.tokens(in: command)
    #expect(
      tokens.map(\.kind) == [
        .command, .variable, .variable, .variable, .variable, .variable, .variable,
      ])
    #expect(
      tokens.dropFirst().map { text($0, in: command) }
        == ["$HOME", "${PATH}", "$1", "$@", "$?", "$$"])
  }

  @Test func highlightsOperatorVariety() {
    let command = "a || b && c | d ; e & f >> g > h < i 2>&1 2> j &> k (l) $(m)"
    let tokens = CommandHighlighter.tokens(in: command)
    let operators = tokens.filter { $0.kind == .operator }.map { text($0, in: command) }
    #expect(
      operators == [
        "||", "&&", "|", ";", "&", ">>", ">", "<", "2>&1", "2>", "&>", "(", ")", "$(", ")",
      ])
  }

  @Test func highlightsCommandAfterEachOperator() {
    let command = "ls | grep foo && echo done ; pwd & (whoami)"
    let tokens = CommandHighlighter.tokens(in: command)
    let commands = tokens.filter { $0.kind == .command }.map { text($0, in: command) }
    #expect(commands == ["ls", "grep", "echo", "pwd", "whoami"])
  }

  @Test func highlightsFlagsOnlyAfterTheCommandWord() {
    let command = "grep -R --color=auto needle"
    let tokens = CommandHighlighter.tokens(in: command)
    #expect(tokens.map(\.kind) == [.command, .flag, .flag])
    #expect(tokens.map { text($0, in: command) } == ["grep", "-R", "--color=auto"])
  }

  @Test func highlightsCommentToEndOfLine() {
    let command = "ls -la # list files\necho next"
    let tokens = CommandHighlighter.tokens(in: command)
    #expect(tokens.map(\.kind) == [.command, .flag, .comment, .command])
    #expect(text(tokens[2], in: command) == "# list files")
  }

  @Test func skipsLeadingAssignmentWordsWhenFindingTheCommand() {
    let command = "FOO=bar BAZ=1 ls -la"
    let tokens = CommandHighlighter.tokens(in: command)
    #expect(tokens.map(\.kind) == [.command, .flag])
    #expect(tokens.map { text($0, in: command) } == ["ls", "-la"])
  }

  @Test func tokensAreAscendingAndNonOverlapping() {
    let command = "git commit -m \"fix: $BUG\" && git push origin main # done"
    let tokens = CommandHighlighter.tokens(in: command)
    for (previous, current) in zip(tokens, tokens.dropFirst()) {
      #expect(previous.range.upperBound <= current.range.lowerBound)
    }
  }
}
