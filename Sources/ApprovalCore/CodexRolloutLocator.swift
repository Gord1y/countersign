import Foundation

public enum CodexRolloutLocator {
  public static let defaultMaxDays = 14

  public static func find(
    sessionID: String, sessionsDirectory: URL, maxDays: Int = defaultMaxDays
  ) -> String? {
    let suffix = "-\(sessionID).jsonl"
    var daysLeft = maxDays
    for year in numberedFolders(in: sessionsDirectory) {
      for month in numberedFolders(in: year) {
        for day in numberedFolders(in: month) {
          guard daysLeft > 0 else { return nil }
          daysLeft -= 1
          if let match = rollout(in: day, endingWith: suffix) {
            return match
          }
        }
      }
    }
    return nil
  }

  private static func numberedFolders(in directory: URL) -> [URL] {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isDirectoryKey])
    else { return [] }
    return
      entries
      .compactMap { entry -> (number: Int, url: URL)? in
        guard let number = Int(entry.lastPathComponent),
          (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { return nil }
        return (number, entry)
      }
      .sorted { $0.number > $1.number }
      .map(\.url)
  }

  private static func rollout(in day: URL, endingWith suffix: String) -> String? {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: day, includingPropertiesForKeys: [.isRegularFileKey])
    else { return nil }
    return
      entries
      .filter { entry in
        let name = entry.lastPathComponent
        return name.hasPrefix("rollout-") && name.hasSuffix(suffix)
          && (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
      }
      .map(\.path)
      .sorted()
      .first
  }
}
