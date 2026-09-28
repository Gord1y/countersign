import Foundation

public enum HomePath {
  public static func abbreviating(_ path: String, relativeTo home: URL) -> String {
    let normalizedHome = normalized(home.path)
    guard !normalizedHome.isEmpty, normalizedHome != "/" else { return path }
    if path == normalizedHome {
      return "~"
    }
    let prefix = normalizedHome + "/"
    guard path.hasPrefix(prefix) else { return path }
    return "~/" + path.dropFirst(prefix.count)
  }

  private static func normalized(_ path: String) -> String {
    path.hasSuffix("/") && path != "/" ? String(path.dropLast()) : path
  }
}
