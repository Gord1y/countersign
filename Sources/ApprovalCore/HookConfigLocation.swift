import Foundation

public struct HookConfigLocation: Sendable, Equatable {
  public let host: Host
  public let directory: URL
  public let file: URL
  public let hostDirectories: [URL]

  public init(host: Host, directory: URL, file: URL, hostDirectories: [URL]? = nil) {
    self.host = host
    self.directory = directory
    self.file = file
    self.hostDirectories = hostDirectories ?? [directory]
  }

  public var hostDirectoryPaths: String {
    hostDirectories.map(\.path).joined(separator: ", ")
  }

  public static func location(for host: Host, environment: [String: String], home: URL)
    -> HookConfigLocation
  {
    let directory: URL
    let fileName: String
    var hostDirectories: [URL]?
    switch host {
    case .claude:
      directory =
        configuredDirectory(environment["CLAUDE_CONFIG_DIR"])
        ?? home.appendingPathComponent(".claude")
      fileName = "settings.json"
    case .codex:
      directory =
        configuredDirectory(environment["CODEX_HOME"]) ?? home.appendingPathComponent(".codex")
      fileName = "hooks.json"
    case .cursor:
      directory = home.appendingPathComponent(".cursor")
      fileName = "hooks.json"
    case .antigravity:
      let gemini = home.appendingPathComponent(".gemini")
      directory = gemini.appendingPathComponent("config")
      fileName = "hooks.json"
      hostDirectories = ["antigravity-cli", "antigravity", "antigravity-ide"].map {
        gemini.appendingPathComponent($0)
      }
    }
    return HookConfigLocation(
      host: host, directory: directory, file: directory.appendingPathComponent(fileName),
      hostDirectories: hostDirectories)
  }

  private static func configuredDirectory(_ value: String?) -> URL? {
    guard let value, !value.isEmpty else { return nil }
    return URL(fileURLWithPath: value, isDirectory: true)
  }
}
