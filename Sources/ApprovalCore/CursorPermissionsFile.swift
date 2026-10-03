import Foundation

public enum CursorPermissionsFile {
  public static func userFile(home: URL) -> URL {
    home
      .appendingPathComponent(".cursor")
      .appendingPathComponent("permissions.json")
  }

  public static func workspaceFile(root: URL) -> URL {
    root
      .appendingPathComponent(".cursor")
      .appendingPathComponent("permissions.json")
  }

  public static func terminalAllowlist(in data: Data) -> [String]? {
    let decoder = JSONDecoder()
    decoder.allowsJSON5 = true
    guard
      let root = try? decoder.decode(JSONValue.self, from: data),
      let entries = root["terminalAllowlist"]?.arrayValue
    else { return nil }
    var patterns: [String] = []
    for entry in entries {
      guard let pattern = entry.stringValue else { return nil }
      patterns.append(pattern)
    }
    return patterns
  }

  public static func terminalAllowlist(at url: URL) -> [String]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return terminalAllowlist(in: data)
  }
}
