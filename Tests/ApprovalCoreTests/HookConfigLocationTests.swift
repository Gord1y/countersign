import Foundation
import Testing

@testable import ApprovalCore

private let home = URL(fileURLWithPath: "/Users/dev")

@Suite struct HookConfigLocationTests {
  @Test func defaultsToTheHostsHomeDirectories() {
    let claude = HookConfigLocation.location(for: .claude, environment: [:], home: home)
    #expect(claude.host == .claude)
    #expect(claude.directory.path == "/Users/dev/.claude")
    #expect(claude.file.path == "/Users/dev/.claude/settings.json")
    let codex = HookConfigLocation.location(for: .codex, environment: [:], home: home)
    #expect(codex.host == .codex)
    #expect(codex.directory.path == "/Users/dev/.codex")
    #expect(codex.file.path == "/Users/dev/.codex/hooks.json")
    let cursor = HookConfigLocation.location(for: .cursor, environment: [:], home: home)
    #expect(cursor.host == .cursor)
    #expect(cursor.directory.path == "/Users/dev/.cursor")
    #expect(cursor.file.path == "/Users/dev/.cursor/hooks.json")
  }

  @Test func keepsCursorInTheHomeDirectoryWhateverTheOtherHostsSay() {
    let environment = ["CLAUDE_CONFIG_DIR": "/tmp/claude-config", "CODEX_HOME": "/tmp/codex-home"]
    #expect(
      HookConfigLocation.location(for: .cursor, environment: environment, home: home).file.path
        == "/Users/dev/.cursor/hooks.json")
  }

  @Test func followsTheConfiguredDirectories() {
    let environment = ["CLAUDE_CONFIG_DIR": "/tmp/claude-config", "CODEX_HOME": "/tmp/codex-home"]
    #expect(
      HookConfigLocation.location(for: .claude, environment: environment, home: home).file.path
        == "/tmp/claude-config/settings.json")
    #expect(
      HookConfigLocation.location(for: .codex, environment: environment, home: home).file.path
        == "/tmp/codex-home/hooks.json")
  }

  @Test func ignoresEmptyConfiguredDirectories() {
    let environment = ["CLAUDE_CONFIG_DIR": "", "CODEX_HOME": ""]
    #expect(
      HookConfigLocation.location(for: .claude, environment: environment, home: home).file.path
        == "/Users/dev/.claude/settings.json")
    #expect(
      HookConfigLocation.location(for: .codex, environment: environment, home: home).file.path
        == "/Users/dev/.codex/hooks.json")
  }

  @Test func detectsAntigravityByAnyOfItsAppDirectories() {
    let environment = ["CLAUDE_CONFIG_DIR": "/tmp/claude-config", "CODEX_HOME": "/tmp/codex-home"]
    let antigravity = HookConfigLocation.location(
      for: .antigravity, environment: environment, home: home)
    #expect(antigravity.host == .antigravity)
    #expect(antigravity.directory.path == "/Users/dev/.gemini/config")
    #expect(antigravity.file.path == "/Users/dev/.gemini/config/hooks.json")
    #expect(
      antigravity.hostDirectories.map(\.path) == [
        "/Users/dev/.gemini/antigravity-cli", "/Users/dev/.gemini/antigravity",
        "/Users/dev/.gemini/antigravity-ide",
      ])
    #expect(
      antigravity.hostDirectoryPaths
        == "/Users/dev/.gemini/antigravity-cli, /Users/dev/.gemini/antigravity, /Users/dev/.gemini/antigravity-ide"
    )
  }

  @Test func detectsTheOtherHostsByTheirOwnDirectory() {
    for host in [ApprovalCore.Host.claude, .codex, .cursor] {
      let location = HookConfigLocation.location(for: host, environment: [:], home: home)
      #expect(location.hostDirectories == [location.directory])
      #expect(location.hostDirectoryPaths == location.directory.path)
    }
    let built = HookConfigLocation(
      host: .claude, directory: home, file: home.appendingPathComponent("settings.json"))
    #expect(built.hostDirectories == [home])
  }
}
