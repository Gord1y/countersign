import Testing

@testable import ApprovalCore

@Suite struct SettingsPromptTests {
  @Test func pointsAnAgentAtTheFileAndTheSchema() {
    #expect(
      SettingsPrompt.text(configPath: "/Users/dev/.config/countersign/config.json")
        == "Change my Countersign settings in /Users/dev/.config/countersign/config.json:"
        + " <what you want>. The file follows the JSON Schema at"
        + " https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json;"
        + " keep every other key as it is.")
  }

  @Test func pointsAtTheSchemaInTheRepository() {
    #expect(
      SettingsPrompt.schemaURL
        == "https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json")
  }

  @Test func linksTheSchemaTheStarterFileNames() {
    #expect(ConfigFileStarter.contents.contains(SettingsPrompt.schemaURL))
  }
}
