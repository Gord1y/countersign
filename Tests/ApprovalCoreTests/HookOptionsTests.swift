import Testing

@testable import ApprovalCore

@Suite struct HookOptionsTests {
  @Test func requiresHost() {
    #expect(HookOptions.parse([]) == nil)
    #expect(HookOptions.parse(["claude"]) == nil)
  }

  @Test func parsesHost() {
    #expect(HookOptions.parse(["--host", "claude"]) == HookOptions(host: .claude))
    #expect(HookOptions.parse(["--host", "antigravity"]) == HookOptions(host: .antigravity))
  }

  @Test func rejectsAnUnknownHost() {
    #expect(HookOptions.parse(["--host", "gpt"]) == nil)
  }

  @Test func rejectsAMissingHostValue() {
    #expect(HookOptions.parse(["--host"]) == nil)
  }

  @Test func rejectsASettingAfterTheHost() {
    #expect(HookOptions.parse(["--host", "claude", "--grace", "3"]) == nil)
  }

  @Test func rejectsAnUnknownFlag() {
    #expect(HookOptions.parse(["--host", "claude", "--bogus"]) == nil)
    #expect(HookOptions.parse(["--bogus", "--host", "claude"]) == nil)
  }

  @Test func rejectsATrailingBareValue() {
    #expect(HookOptions.parse(["--host", "claude", "extra"]) == nil)
  }

  @Test func rejectsARepeatedHost() {
    #expect(HookOptions.parse(["--host", "claude", "--host", "codex"]) == nil)
  }

  @Test func theTwoArgumentFormHasNoEvent() {
    #expect(HookOptions.parse(["--host", "claude"])?.event == nil)
  }

  @Test func parsesTheWaitingEvent() {
    #expect(
      HookOptions.parse(["--host", "claude", "--event", "waiting"])
        == HookOptions(host: .claude, event: .waiting))
    #expect(
      HookOptions.parse(["--host", "antigravity", "--event", "waiting"])
        == HookOptions(host: .antigravity, event: .waiting))
  }

  @Test func rejectsAnUnknownEventOrAMissingEventValue() {
    #expect(HookOptions.parse(["--host", "claude", "--event", "stop"]) == nil)
    #expect(HookOptions.parse(["--host", "claude", "--event"]) == nil)
    #expect(HookOptions.parse(["--host", "claude", "--event", "waiting", "extra"]) == nil)
    #expect(HookOptions.parse(["--host", "claude", "--other", "waiting"]) == nil)
    #expect(HookOptions.parse(["--event", "waiting", "--host", "claude"]) == nil)
  }
}
