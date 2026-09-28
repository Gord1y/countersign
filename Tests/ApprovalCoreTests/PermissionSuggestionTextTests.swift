import Testing

@testable import ApprovalCore

@Suite struct PermissionSuggestionTextTests {
  private func fixtureSuggestions() throws -> [PermissionSuggestion] {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-bash-subagent"))
    guard case .permission(let prompt) = request.kind else {
      Issue.record("expected permission")
      return []
    }
    return prompt.suggestions
  }

  private func rule(_ ruleContent: String?, destination: String) -> PermissionSuggestion {
    var rule: [String: JSONValue] = ["toolName": .string("Bash")]
    if let ruleContent {
      rule["ruleContent"] = .string(ruleContent)
    }
    return PermissionSuggestion(
      raw: .object([
        "type": .string("addRules"),
        "rules": .array([.object(rule)]),
        "behavior": .string("allow"),
        "destination": .string(destination),
      ]),
      label: "")
  }

  @Test func aRuleShowsTheExactRuleAndThatItIsKeptForThisProjectOnThisMac() throws {
    let suggestions = try fixtureSuggestions()
    try #require(suggestions.count == 2)
    let text = PermissionSuggestionText(suggestions[0])
    #expect(text.title == "Bash(git push --force-with-lease origin *)")
    #expect(text.detail == "This project, on this Mac")
  }

  @Test func aDirectoryShowsItsPathAndThatItIsKeptForThisSession() throws {
    let suggestions = try fixtureSuggestions()
    try #require(suggestions.count == 2)
    let text = PermissionSuggestionText(suggestions[1])
    #expect(text.title == "Allow access to /Users/dev/Projects/shop-api")
    #expect(text.detail == "This session")
  }

  @Test func projectSettingsAreSharedWithTheProject() {
    let text = PermissionSuggestionText(rule("npm test", destination: "projectSettings"))
    #expect(text.title == "Bash(npm test)")
    #expect(text.detail == "This project, shared")
  }

  @Test func userSettingsApplyToAllProjects() {
    let text = PermissionSuggestionText(rule("npm test", destination: "userSettings"))
    #expect(text.detail == "All projects")
  }

  @Test func anUnknownDestinationHasNoSecondLine() {
    let text = PermissionSuggestionText(rule("npm test", destination: "cliArg"))
    #expect(text.title == "Bash(npm test)")
    #expect(text.detail == nil)
  }

  @Test func aRuleWithoutContentIsJustTheToolName() {
    #expect(PermissionSuggestionText(rule("", destination: "session")).title == "Bash")
    #expect(PermissionSuggestionText(rule(nil, destination: "session")).title == "Bash")
  }

  @Test func anyOtherSuggestionKeepsItsLabel() {
    let suggestion = PermissionSuggestion(
      raw: .object(["type": .string("setMode"), "mode": .string("acceptEdits")]),
      label: "Allow and switch to acceptEdits")
    let text = PermissionSuggestionText(suggestion)
    #expect(text.title == "Allow and switch to acceptEdits")
    #expect(text.detail == nil)
  }
}
