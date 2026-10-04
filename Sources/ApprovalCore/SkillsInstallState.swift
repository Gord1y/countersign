import Foundation

public struct SkillsInstallState: Equatable, Sendable {
  public struct ManifestEntry: Equatable, Sendable {
    public let agent: String
    public let skill: String
    public let version: String
    public let file: String
    public let sha256: String

    public init(agent: String, skill: String, version: String, file: String, sha256: String) {
      self.agent = agent
      self.skill = skill
      self.version = version
      self.file = file
      self.sha256 = sha256
    }
  }

  public static let sourcesFileName = "sources.tsv"
  public static let additionsFileName = "additions.tsv"
  public static let manifestFileName = "manifest.tsv"
  public static let backupsFolderName = "backups"

  public let sources: [URL]
  public let additions: [URL]
  public let manifest: [ManifestEntry]
  public let backups: [String]

  public var setupFolder: URL? {
    sources.first
  }

  public static func read(directory: URL) -> SkillsInstallState {
    SkillsInstallState(
      sources: folderList(from: text(of: directory.appendingPathComponent(sourcesFileName))),
      additions: folderList(from: text(of: directory.appendingPathComponent(additionsFileName))),
      manifest: manifestEntries(from: text(of: directory.appendingPathComponent(manifestFileName))),
      backups: backupNames(in: directory.appendingPathComponent(backupsFolderName)))
  }

  public static func folderList(from text: String) -> [URL] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
      let path = trimmingTrailingWhitespace(String(line))
      guard path.hasPrefix("/") else { return nil }
      return URL(fileURLWithPath: path)
    }
  }

  public static func manifestEntries(from text: String) -> [ManifestEntry] {
    text.split(whereSeparator: \.isNewline).compactMap { line in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 5, isSHA256(fields[4]) else { return nil }
      return ManifestEntry(
        agent: String(fields[0]), skill: String(fields[1]), version: String(fields[2]),
        file: String(fields[3]), sha256: String(fields[4]))
    }
  }

  private static func text(of file: URL) -> String {
    guard let data = try? Data(contentsOf: file) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }

  private static func backupNames(in folder: URL) -> [String] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])) ?? []
    return
      entries
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .map(\.lastPathComponent)
      .sorted(by: >)
  }

  private static func trimmingTrailingWhitespace(_ line: String) -> String {
    var trimmed = Substring(line)
    while let last = trimmed.last, last.isWhitespace {
      trimmed.removeLast()
    }
    return String(trimmed)
  }

  private static func isSHA256(_ field: Substring) -> Bool {
    field.utf8.count == 64
      && field.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
  }
}

public struct InstalledSkill: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case linked(target: URL)
    case copied
  }

  public let agent: String
  public let name: String
  public let kind: Kind

  public init(agent: String, name: String, kind: Kind) {
    self.agent = agent
    self.name = name
    self.kind = kind
  }

  public static func scan(agent: String, directory: URL) -> [InstalledSkill] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.sorted().compactMap { name in
      guard !name.hasPrefix(".") else { return nil }
      let entry = directory.appendingPathComponent(name)
      if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path) {
        let target =
          destination.hasPrefix("/")
          ? URL(fileURLWithPath: destination)
          : directory.appendingPathComponent(destination)
        return InstalledSkill(
          agent: agent, name: name, kind: .linked(target: target.standardizedFileURL))
      }
      var isDirectory: ObjCBool = false
      guard
        FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else { return nil }
      return InstalledSkill(agent: agent, name: name, kind: .copied)
    }
  }
}
