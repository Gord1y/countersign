import Foundation
import Testing

@testable import ApprovalCore

@Suite struct TimeoutHandBackTests {
  @Test func handsBackAMinuteBeforeTheTimeoutSetupWrites() {
    #expect(TimeoutHandBack.entryTimeoutSeconds == 3600)
    #expect(TimeoutHandBack.entryTimeoutSeconds == HookSetup.timeoutSeconds)
    #expect(TimeoutHandBack.marginSeconds == 60)
    #expect(TimeoutHandBack.deadline(for: .cursor) == .seconds(3540))
    #expect(TimeoutHandBack.deadline(for: .antigravity) == .seconds(3540))
  }

  @Test func onlyCursorAndAntigravityHandBack() {
    #expect(TimeoutHandBack.deadline(for: .claude) == nil)
    #expect(TimeoutHandBack.deadline(for: .codex) == nil)
    #expect(!TimeoutHandBack.isDue(host: .claude, elapsed: .seconds(86_400)))
    #expect(!TimeoutHandBack.isDue(host: .codex, elapsed: .seconds(86_400)))
  }

  @Test func isDueFromTheDeadlineOn() {
    for host in [ApprovalCore.Host.cursor, .antigravity] {
      #expect(!TimeoutHandBack.isDue(host: host, elapsed: .zero))
      #expect(!TimeoutHandBack.isDue(host: host, elapsed: .seconds(3539) + .milliseconds(999)))
      #expect(TimeoutHandBack.isDue(host: host, elapsed: .seconds(3540)))
      #expect(TimeoutHandBack.isDue(host: host, elapsed: .seconds(3600)))
    }
  }

  @Test func logsWhyItHandedBack() {
    #expect(TimeoutHandBack.logLine(for: .cursor) == "handed back: cursor timeout near")
    #expect(TimeoutHandBack.logLine(for: .antigravity) == "handed back: antigravity timeout near")
  }
}
