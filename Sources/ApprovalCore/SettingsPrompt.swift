import Foundation

public enum SettingsPrompt {
  public static let schemaURL =
    "https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json"

  public static func text(configPath: String) -> String {
    "Change my Countersign settings in \(configPath): <what you want>. The file follows the JSON"
      + " Schema at \(schemaURL); keep every other key as it is."
  }
}
