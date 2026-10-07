import Foundation

public enum GuardedFolder {
  private static let homePlaces: [(components: [String], name: String)] = [
    (["Documents"], "Documents"),
    (["Desktop"], "Desktop"),
    (["Downloads"], "Downloads"),
    (["Library", "Mobile Documents"], "iCloud Drive"),
  ]

  public static func isGuarded(_ folder: URL, home: URL) -> Bool {
    placeName(of: folder, home: home) != nil
  }

  public static func placeName(of folder: URL, home: URL) -> String? {
    let homes = [home, home.resolvingSymlinksInPath()]
    if let asWritten = place(of: folder, homes: homes) { return asWritten }
    return place(of: folder.resolvingSymlinksInPath(), homes: homes)
  }

  private static func place(of folder: URL, homes: [URL]) -> String? {
    let components = folder.standardizedFileURL.pathComponents
    if components.count > 2, components[1] == "Volumes" { return "an external drive" }
    for home in homes {
      let homeComponents = home.standardizedFileURL.pathComponents
      guard components.count >= homeComponents.count,
        Array(components.prefix(homeComponents.count)) == homeComponents
      else { continue }
      let relative = Array(components.dropFirst(homeComponents.count))
      for place in homePlaces where relative.starts(with: place.components) {
        return place.name
      }
    }
    return nil
  }
}

public enum SkillFolderApprovals {
  public static func read(_ file: URL) -> Set<String> {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    return Set(
      text.split(whereSeparator: \.isNewline).map { String($0) }.filter { !$0.isEmpty })
  }

  public static func add(_ folder: URL, to file: URL) throws {
    let path = folder.standardizedFileURL.path
    var lines =
      (try? String(contentsOf: file, encoding: .utf8))
      .map { $0.split(whereSeparator: \.isNewline).map { String($0) } } ?? []
    guard !lines.contains(path) else { return }
    lines.append(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: file, options: .atomic)
  }
}
