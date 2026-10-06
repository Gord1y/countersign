import Foundation
import Testing

@testable import ApprovalCore

@Suite struct AppPathsTests {
  @Test func computesPathsRelativeToHome() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let paths = AppPaths(home: home)
    #expect(
      paths.supportDirectory.path == "/Users/dev/Library/Application Support/Countersign"
    )
    #expect(paths.logsDirectory.path == "/Users/dev/Library/Logs/Countersign")
    #expect(paths.claudeSessionsDirectory.path == "/Users/dev/.claude/sessions")
    #expect(paths.queueDirectory.path == "/Users/dev/Library/Application Support/Countersign/queue")
    #expect(
      paths.contextCheckpointsDirectory.path
        == "/Users/dev/Library/Application Support/Countersign/context"
    )
    #expect(
      paths.waitingDirectory.path
        == "/Users/dev/Library/Application Support/Countersign/waiting"
    )
    #expect(
      paths.displayLockFile.path
        == "/Users/dev/Library/Application Support/Countersign/queue/display.lock"
    )
    #expect(paths.pauseFile.path == "/Users/dev/Library/Application Support/Countersign/paused")
    #expect(
      paths.quietFile.path == "/Users/dev/Library/Application Support/Countersign/quiet-until"
    )
    #expect(
      paths.quietHoursSkippedFile.path
        == "/Users/dev/Library/Application Support/Countersign/quiet-hours-skipped-until"
    )
    #expect(
      paths.codexHookTrustFile.path
        == "/Users/dev/Library/Application Support/Countersign/codex-hook-trust.json"
    )
    #expect(
      paths.tourShownFile.path
        == "/Users/dev/Library/Application Support/Countersign/tour-shown"
    )
    #expect(
      paths.lastSeenVersionFile.path
        == "/Users/dev/Library/Application Support/Countersign/last-seen-version"
    )
    #expect(
      paths.companionLockFile.path
        == "/Users/dev/Library/Application Support/Countersign/companion.lock"
    )
    #expect(
      paths.updateCheckFile.path
        == "/Users/dev/Library/Application Support/Countersign/update-check.json"
    )
    #expect(paths.logFile.path == "/Users/dev/Library/Logs/Countersign/countersign.log")
  }

  @Test func configPathFallsBackToHomeConfigWithNoXDGConfigHome() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let paths = AppPaths(home: home)
    #expect(paths.configDirectory.path == "/Users/dev/.config/countersign")
    #expect(paths.configFile.path == "/Users/dev/.config/countersign/config.json")
  }

  @Test func configPathFallsBackToHomeConfigWithEmptyXDGConfigHome() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let paths = AppPaths(home: home, xdgConfigHome: "")
    #expect(paths.configDirectory.path == "/Users/dev/.config/countersign")
  }

  @Test func configPathUsesXDGConfigHomeWhenSet() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let paths = AppPaths(home: home, xdgConfigHome: "/Users/dev/.xdgconfig")
    #expect(paths.configDirectory.path == "/Users/dev/.xdgconfig/countersign")
    #expect(paths.configFile.path == "/Users/dev/.xdgconfig/countersign/config.json")
  }

  @Test func claudeSessionsFallsBackToHomeClaudeWithNoConfigDir() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let paths = AppPaths(home: home)
    #expect(paths.claudeSessionsDirectory.path == "/Users/dev/.claude/sessions")
  }

  @Test func claudeSessionsFallsBackToHomeClaudeWithEmptyConfigDir() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let paths = AppPaths(home: home, claudeConfigDir: "")
    #expect(paths.claudeSessionsDirectory.path == "/Users/dev/.claude/sessions")
  }

  @Test func claudeSessionsUsesConfigDirWhenSet() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let paths = AppPaths(home: home, claudeConfigDir: "/Users/dev/.claude-work")
    #expect(paths.claudeSessionsDirectory.path == "/Users/dev/.claude-work/sessions")
  }

  @Test func doesNotCreateAnyDirectories() {
    let home = URL(fileURLWithPath: "/tmp/countersign-app-paths-test-\(UUID().uuidString)")
    let paths = AppPaths(home: home)
    _ = paths.supportDirectory
    #expect(!FileManager.default.fileExists(atPath: paths.supportDirectory.path))
  }
}
