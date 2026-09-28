import Foundation
import Testing

@testable import ApprovalCore

private let ourKey = "/Users/dev/.codex/hooks.json:permission_request:0:0"
private let capturedHash =
  "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

private func table(_ text: String) -> CodexTrustTable? {
  CodexTrustTable(configBytes: Array(text.utf8))
}

@Suite struct CodexTrustTableTests {
  @Test func readsTheCapturedTable() throws {
    let bytes = Array(try FixtureLoader.data("codex-config-hook-trust", withExtension: "toml"))
    #expect(
      CodexTrustTable(configBytes: bytes) == CodexTrustTable(trustedHashes: [ourKey: capturedHash]))
    #expect(CodexTrustTable.read(.bytes(bytes))?.trustedHashes == [ourKey: capturedHash])
  }

  @Test func ignoresUnrelatedTablesBeforeAndAfter() {
    let text = #"""
      model = "gpt-5-codex"
      approval_policy = "on-request"
      notify = ["terminal-notifier", "-title", "Codex"]
      greeting = "h\u00e9llo \"there\" 😀"

      [mcp_servers.docs]
      command = "npx"
      args = [
        "-y",
        "@example/docs-server", # pinned
      ]
      env = { "API_HOST" = "example.test", PORT = "8080" }

      [projects."/Users/dev/.codex/hooks.json:permission_request:0:0"]
      trusted_hash = "sha256:not-a-hook"
      trust_level = "trusted"

      [hooks.state."/Users/dev/.codex/hooks.json:permission_request:0:0"]
      trusted_hash = "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

      [profiles.fast]
      model = "gpt-5-mini"
      started = 1979-05-27 07:32:00Z
      matrix = [
        [1, 2],
        [3, 4],
      ]
      """#
    #expect(table(text) == CodexTrustTable(trustedHashes: [ourKey: capturedHash]))
  }

  @Test func readsEveryHookTableAndSkipsTheirOtherKeys() {
    let text = #"""
      [hooks.state."/Users/dev/.codex/hooks.json:permission_request:0:0"]
      trusted_hash = "sha256:a"
      [hooks.state."/Users/dev/.codex/hooks.json:permission_request:1:0"]
      enabled = true
      trusted_hash = "sha256:b"
      note = { text = "x" }
      [hooks.state."/Users/dev/.codex/hooks.json:pre_tool_use:0:0"]
      enabled = false
      [hooks]
      other = 1
      [hooks.PermissionRequest]
      state = "unrelated"
      [hooks.state]

      """#
    #expect(
      table(text)
        == CodexTrustTable(trustedHashes: [
          ourKey: "sha256:a",
          "/Users/dev/.codex/hooks.json:permission_request:1:0": "sha256:b",
        ]))
  }

  @Test func allowsWhitespaceCommentsQuotedNamesAndWindowsLineEndings() {
    let spaced =
      "# settings\r\n  [ hooks . state . \"\(ourKey)\" ]  # ours\r\n"
      + "\ttrusted_hash   =   \"sha256:a\"  # trusted\r\n\r\n"
    #expect(table(spaced) == CodexTrustTable(trustedHashes: [ourKey: "sha256:a"]))
    let quoted = "[\"hooks\".'state'.\"\(ourKey)\"]\n\"trusted_hash\" = \"sha256:b\""
    #expect(table(quoted) == CodexTrustTable(trustedHashes: [ourKey: "sha256:b"]))
  }

  @Test func decodesEscapesInTheHookKey() {
    let text =
      #"[hooks.state."/Users/a \"b\" \\c \u00e9\U0001F600\b\t\n\f\r:permission_request:0:0"]"#
      + "\ntrusted_hash = \"sha256:a\"\n"
    let key = "/Users/a \"b\" \\c \u{E9}\u{1F600}\u{8}\t\n\u{C}\r:permission_request:0:0"
    #expect(table(text) == CodexTrustTable(trustedHashes: [key: "sha256:a"]))
  }

  @Test func holdsNoHashesForAnEmptyOrUnrelatedFile() {
    #expect(table("") == CodexTrustTable(trustedHashes: [:]))
    #expect(table("\n# nothing yet\n\n") == CodexTrustTable(trustedHashes: [:]))
    #expect(table("model = \"o3\"\n") == CodexTrustTable(trustedHashes: [:]))
  }

  @Test func cannotTellWithoutReadableUTF8() {
    #expect(CodexTrustTable.read(.missing) == nil)
    #expect(CodexTrustTable.read(.unreadable("Permission denied")) == nil)
    #expect(CodexTrustTable.read(.bytes([0xFF, 0xFE, 0x5B])) == nil)
    #expect(CodexTrustTable(configBytes: Array("model = \"".utf8) + [0xC3]) == nil)
  }

  @Test(arguments: [
    "[hooks]\nstate = { \"K\" = { trusted_hash = \"sha256:a\" } }\n",
    "[hooks]\nstate.\"K\".trusted_hash = \"sha256:a\"\n",
    "hooks.state.\"K\".trusted_hash = \"sha256:a\"\n",
    "hooks = { state = { \"K\" = { trusted_hash = \"sha256:a\" } } }\n",
    "[hooks.state]\n\"K\".trusted_hash = \"sha256:a\"\n",
    "[hooks.state]\n\"K\" = { trusted_hash = \"sha256:a\" }\n",
    "[[hooks.state.\"K\"]]\ntrusted_hash = \"sha256:a\"\n",
    "[[hooks.state]]\n",
    "[[hooks]]\n",
    "[hooks.state.'K']\ntrusted_hash = \"sha256:a\"\n",
    "[hooks.state.K]\ntrusted_hash = \"sha256:a\"\n",
    "[hooks.state.\"K\".more]\ntrusted_hash = \"sha256:a\"\n",
    "[hooks.state.\"K\"]\ntrusted_hash = \"\"\"sha256:a\"\"\"\n",
    "[hooks.state.\"K\"]\ntrusted_hash = \"\"\"\nsha256:a\"\"\"\n",
    "[hooks.state.\"K\"]\ntrusted_hash = '''sha256:a'''\n",
    "[hooks.state.\"K\"]\ntrusted_hash = 'sha256:a'\n",
    "[hooks.state.\"K\"]\ntrusted_hash = 1\n",
    "[hooks.state.\"K\"]\ntrusted_hash.value = \"sha256:a\"\n",
    "[hooks.state.\"K\"]\ntrusted_hash = \"sha256:a\"\ntrusted_hash = \"sha256:a\"\n",
    "[hooks.state.\"K\"]\ntrusted_hash = \"sha256:a\"\n[hooks.state.\"K\"]\n",
    "[hooks.state.\"K\"]\n[hooks.state.\"\\u004B\"]\n",
  ])
  func cannotTellForAnotherShapeOfHookState(_ text: String) {
    #expect(table(text) == nil)
  }

  @Test(arguments: [
    "model = \"unterminated\n",
    "model = \"line\nbreak\"\n",
    "model = 'unterminated\n",
    "model = 'unterminated",
    "model = \"ends with a backslash\\",
    "args = [\n  \"a\",\n",
    "args = [1, 2}\n",
    "args = [\"a\n",
    "text = \"\"\"never closed\n",
    "text = '''never closed\n",
    "text = \"\"\"six quotes\"\"\"\"\"\"\n",
    "key\n",
    "key.",
    "= 1\n",
    "key =\n",
    "key = # nothing\n",
    "key = ",
    "key = 1\rnext = 2\n",
    "key = \"a\" junk\n",
    "[table\n",
    "[table] junk\n",
    "[[table]\n",
    "\"\"\"key\"\"\" = 1\n",
    "'''key''' = 1\n",
    "\"a\\qb\" = 1\n",
    "\"a\\u12\" = 1\n",
    "\"a\\u+123\" = 1\n",
    "\"a\\u1",
    "\"a\\uD800\" = 1\n",
    "\"a\\",
    "\"a",
    "\"a\nb\" = 1\n",
    "'a\nb' = 1\n",
    "'a",
    "[hooks.state.\"K\"]\ntrusted_hash = \"sha256:a\n",
  ])
  func cannotTellWhenTheFileIsNotTOML(_ text: String) {
    #expect(table(text) == nil)
  }

  @Test func skipsValuesThatOnlyLookLikeHookState() {
    let values = #"""
      notes = """
      [hooks.state."/Users/dev/.codex/hooks.json:permission_request:0:0"]
      trusted_hash = "sha256:fake" \""" and a slash \\"""
      quoted = """ends with two quotes"""""
      literal = '''
      [hooks.state."/Users/dev/.codex/hooks.json:permission_request:0:0"]
      '''
      escaped = "a \" [hooks.state.\"K\"] \\"
      nested = [ "]", '[', { a = "}" }, # a comment with ]
        [1, 2], ]

      """#
    #expect(table(values) == CodexTrustTable(trustedHashes: [:]))
    let followed = values + "[hooks.state.\"\(ourKey)\"]\ntrusted_hash = \"sha256:real\"\n"
    #expect(table(followed) == CodexTrustTable(trustedHashes: [ourKey: "sha256:real"]))
  }
}
