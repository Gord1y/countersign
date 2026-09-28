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
}
