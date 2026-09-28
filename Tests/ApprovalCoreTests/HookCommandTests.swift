import Foundation
import Testing

@testable import ApprovalCore

private func words(_ command: String, limit: Int = 2) -> [HookCommandWord] {
  HookCommand.words(in: Array(command.unicodeScalars), limit: limit)
}

@Suite struct HookCommandTests {
  @Test func splitsWordsOnWhitespace() {
    #expect(
      words("  /usr/local/bin/countersign\thook --host claude")
        == [
          HookCommandWord(range: 2..<28, value: "/usr/local/bin/countersign"),
          HookCommandWord(range: 29..<33, value: "hook"),
        ])
    #expect(words("a b c", limit: 1) == [HookCommandWord(range: 0..<1, value: "a")])
    #expect(words("   ") == [])
  }

  @Test func readsAQuotedFirstWord() {
    #expect(
      words("'/Users/me/My Tools/countersign' hook")
        == [
          HookCommandWord(range: 0..<32, value: "/Users/me/My Tools/countersign"),
          HookCommandWord(range: 33..<37, value: "hook"),
        ])
    #expect(words("\"/a b/countersign\" hook").first?.value == "/a b/countersign")
    #expect(words("'unterminated hook") == [])
  }

  @Test func recognisesCountersignHookCommands() {
    #expect(HookCommand.isCountersignHook("/opt/homebrew/bin/countersign hook --host claude"))
    #expect(HookCommand.isCountersignHook("countersign hook"))
    #expect(
      HookCommand.isCountersignHook("/Users/x/.local/bin/countersign hook --host codex --verbose"))
    #expect(HookCommand.isCountersignHook("'/Users/me/My Tools/countersign' hook --host claude"))
  }

  @Test func ignoresEverythingElse() {
    #expect(!HookCommand.isCountersignHook("/opt/homebrew/bin/countersign status"))
    #expect(!HookCommand.isCountersignHook("/opt/homebrew/bin/countersign"))
    #expect(!HookCommand.isCountersignHook("/opt/homebrew/bin/countersign-dev hook"))
    #expect(!HookCommand.isCountersignHook("/opt/countersign/bin/other hook"))
    #expect(!HookCommand.isCountersignHook("FOO=1 countersign hook"))
    #expect(!HookCommand.isCountersignHook("~/bin/guard.sh"))
    #expect(!HookCommand.isCountersignHook(""))
  }

  @Test func recognisesTheExecutableByItsBasename() {
    #expect(HookCommand.isCountersignExecutable("/opt/homebrew/bin/countersign"))
    #expect(HookCommand.isCountersignExecutable("countersign"))
    #expect(
      !HookCommand.isCountersignExecutable(
        "/Applications/Countersign.app/Contents/MacOS/Countersign"))
    #expect(!HookCommand.isCountersignExecutable(""))
  }

  @Test func quotesAPathOnlyWhenTheShellNeedsIt() {
    #expect(
      HookCommand.shellWord("/opt/homebrew/bin/countersign") == "/opt/homebrew/bin/countersign")
    #expect(
      HookCommand.shellWord("/a/b-c_d.e+f@g%h:i,j=k/countersign")
        == "/a/b-c_d.e+f@g%h:i,j=k/countersign")
    #expect(
      HookCommand.shellWord("/Users/me/My Tools/countersign") == "'/Users/me/My Tools/countersign'")
    #expect(
      HookCommand.shellWord("/Users/me/it's/countersign") == "'/Users/me/it'\\''s/countersign'")
    #expect(HookCommand.shellWord("/Users/mé/countersign") == "'/Users/mé/countersign'")
    #expect(HookCommand.shellWord("/a/$HOME/countersign") == "'/a/$HOME/countersign'")
    #expect(HookCommand.shellWord("") == "''")
  }

  @Test func namesTheArgumentsSetupWrites() {
    #expect(HookCommand.arguments(for: .cursor) == ["hook", "--host", "cursor"])
  }

  @Test func matchesOnlyTheExactCommandForAPathAndHost() {
    let path = "/opt/homebrew/bin/countersign"
    #expect(HookCommand.isCommand("\(path) hook --host claude", running: path, for: .claude))
    #expect(HookCommand.isCommand(" '\(path)'  hook\t--host claude ", running: path, for: .claude))
    #expect(!HookCommand.isCommand("\(path) hook --host claude", running: path, for: .codex))
    #expect(!HookCommand.isCommand("\(path) hook --host claude x", running: path, for: .claude))
    #expect(!HookCommand.isCommand("\(path) hook", running: path, for: .claude))
    #expect(
      !HookCommand.isCommand("/old/countersign hook --host claude", running: path, for: .claude))
  }

  @Test func buildsTheHookCommandForAHost() {
    #expect(
      HookCommand.command(host: .claude, executablePath: "/opt/homebrew/bin/countersign")
        == "/opt/homebrew/bin/countersign hook --host claude")
    #expect(
      HookCommand.command(host: .codex, executablePath: "/Users/me/My Tools/countersign")
        == "'/Users/me/My Tools/countersign' hook --host codex")
  }
}
