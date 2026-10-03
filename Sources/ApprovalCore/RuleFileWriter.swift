import Foundation

public enum RuleFileWriter {
  public static func add(_ rules: [ApprovalRule], configFile: URL, now: Date = Date()) throws {
    let original = try ConfigFileStore.read(configFile)
    let updated = try ConfigEdit.applying([.addRules(rules)], to: original)
    guard updated != original else { return }
    try FileManager.default.createDirectory(
      at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try ConfigFileStore.write(updated, to: configFile, date: now, backingUp: true)
  }
}
