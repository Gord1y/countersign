import Testing

@testable import ApprovalCore

@Suite struct SetupOptionsTests {
  @Test func defaultsToEveryHostWithQuestions() {
    let options = SetupOptions.parse([])
    #expect(
      options == SetupOptions(assumeYes: false, uninstall: false, host: nil, terminalFlow: false))
    #expect(options?.hosts == [.claude, .codex, .cursor, .antigravity])
  }

  @Test func limitsTheRunToCursor() {
    let options = SetupOptions.parse(["--cli", "--host", "cursor"])
    #expect(
      options == SetupOptions(assumeYes: false, uninstall: false, host: .cursor, terminalFlow: true)
    )
    #expect(options?.hosts == [.cursor])
  }

  @Test func limitsTheRunToAntigravity() {
    let options = SetupOptions.parse(["--cli", "--uninstall", "--host", "antigravity"])
    #expect(
      options
        == SetupOptions(assumeYes: false, uninstall: true, host: .antigravity, terminalFlow: true))
    #expect(options?.hosts == [.antigravity])
  }

  @Test func parsesEveryFlag() {
    let options = SetupOptions.parse(["--cli", "--yes", "--uninstall", "--host", "codex"])
    #expect(
      options == SetupOptions(assumeYes: true, uninstall: true, host: .codex, terminalFlow: true))
    #expect(options?.hosts == [.codex])
  }

  @Test func rejectsAnUnknownOrMissingHost() {
    #expect(SetupOptions.parse(["--host"]) == nil)
    #expect(SetupOptions.parse(["--host", "gpt"]) == nil)
  }

  @Test func rejectsRepeatedFlags() {
    #expect(SetupOptions.parse(["--yes", "--yes"]) == nil)
    #expect(SetupOptions.parse(["--uninstall", "--uninstall"]) == nil)
    #expect(SetupOptions.parse(["--cli", "--cli"]) == nil)
    #expect(SetupOptions.parse(["--host", "claude", "--host", "codex"]) == nil)
  }

  @Test func rejectsUnknownArguments() {
    #expect(SetupOptions.parse(["-y"]) == nil)
    #expect(SetupOptions.parse(["claude"]) == nil)
  }

  @Test func opensTheWindowWithoutArguments() {
    #expect(SetupOptions.mode(for: []) == .window)
  }

  @Test func keepsTheTerminalFlowBehindCLI() {
    #expect(
      SetupOptions.mode(for: ["--cli"])
        == .terminal(
          SetupOptions(assumeYes: false, uninstall: false, host: nil, terminalFlow: true)))
    #expect(
      SetupOptions.mode(for: ["--yes", "--host", "codex", "--cli", "--uninstall"])
        == .terminal(
          SetupOptions(assumeYes: true, uninstall: true, host: .codex, terminalFlow: true)))
  }

  @Test func refusesTerminalFlagsWithoutCLI() {
    #expect(SetupOptions.mode(for: ["--yes"]) == nil)
    #expect(SetupOptions.mode(for: ["--uninstall"]) == nil)
    #expect(SetupOptions.mode(for: ["--host", "claude"]) == nil)
    #expect(SetupOptions.mode(for: ["--window"]) == nil)
    #expect(SetupOptions.mode(for: ["--cli", "--cli"]) == nil)
  }
}
