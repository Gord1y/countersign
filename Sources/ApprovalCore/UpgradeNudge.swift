import Foundation

public enum UpgradeNudge {
  public static func isUpgrade(lastSeenVersion: String?, tourShown: Bool, currentVersion: String)
    -> Bool
  {
    guard let lastSeenVersion else { return tourShown }
    return lastSeenVersion != currentVersion
  }

  public static func needsAgentUpdate(_ statuses: [HostWiringStatus]) -> Bool {
    statuses.contains { status in
      if case .needsUpdate = status { return true }
      return false
    }
  }

  public static func readLastSeenVersion(file: URL) -> String? {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  public static func recordVersion(_ version: String, file: URL) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("\(version)\n".utf8).write(to: file, options: .atomic)
  }
}
