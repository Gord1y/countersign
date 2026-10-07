import Foundation

public struct AppBundleCopyOffer: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case add
    case replaceLink
    case update(from: String)
  }

  public let kind: Kind
  public let source: String
  public let destination: URL
  public let version: String

  public init(kind: Kind, source: String, destination: URL, version: String) {
    self.kind = kind
    self.source = source
    self.destination = destination
    self.version = version
  }
}

public struct AppBundleCopyRefresh: Sendable, Equatable {
  public let source: String
  public let destination: URL
  public let from: String
  public let to: String

  public init(source: String, destination: URL, from: String, to: String) {
    self.source = source
    self.destination = destination
    self.from = from
    self.to = to
  }
}

public enum AppBundleCopy {
  public static let bundleName = "Countersign.app"
  static let cellarMarker = "/Cellar/countersign/"
  static let optDirectory = "/opt/countersign/"
  static let temporaryPrefix = ".Countersign.app.copying-"

  public static func candidate(forResolvedExecutable path: String) -> String {
    URL(fileURLWithPath: path)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(bundleName)
      .standardizedFileURL.path
  }

  public static func stableSource(for candidate: String) -> String {
    guard let marker = candidate.range(of: cellarMarker) else { return candidate }
    let prefix = candidate[..<marker.lowerBound]
    let inKeg = candidate[marker.upperBound...].drop { $0 != "/" }.dropFirst()
    guard !inKeg.isEmpty else { return candidate }
    return String(prefix) + optDirectory + String(inKeg)
  }

  public static func destination(home: URL) -> URL {
    home.appendingPathComponent("Applications").appendingPathComponent(bundleName)
  }

  public static func offer(
    resolvedExecutable: String, home: URL, fileSystem: InstallFileSystem
  ) -> AppBundleCopyOffer? {
    let candidate = candidate(forResolvedExecutable: resolvedExecutable)
    guard fileSystem.kind(candidate) == .directory,
      let version = InstalledCopies.bundleVersion(candidate, fileSystem: fileSystem)
    else { return nil }
    let destination = destination(home: home)
    guard
      let kind = offerKind(
        at: destination, sourceVersion: version, fileSystem: fileSystem)
    else { return nil }
    return AppBundleCopyOffer(
      kind: kind, source: stableSource(for: candidate), destination: destination,
      version: version)
  }

  public static func refresh(
    runningBundle: String, home: URL, fileSystem: InstallFileSystem,
    prefixes: [String] = InstalledCopies.homebrewPrefixes
  ) -> AppBundleCopyRefresh? {
    let destination = destination(home: home)
    guard URL(fileURLWithPath: runningBundle).standardizedFileURL.path == destination.path,
      fileSystem.kind(destination.path) == .directory,
      let copyVersion = InstalledCopies.bundleVersion(destination.path, fileSystem: fileSystem),
      let copyParts = UpdateCheck.semverParts(copyVersion)
    else { return nil }
    for prefix in prefixes {
      let source = prefix + optDirectory + bundleName
      guard let resolved = fileSystem.resolved(source), fileSystem.kind(resolved) == .directory,
        let sourceVersion = InstalledCopies.bundleVersion(source, fileSystem: fileSystem),
        let sourceParts = UpdateCheck.semverParts(sourceVersion),
        copyParts.lexicographicallyPrecedes(sourceParts)
      else { continue }
      return AppBundleCopyRefresh(
        source: source, destination: destination, from: copyVersion, to: sourceVersion)
    }
    return nil
  }

  public static func perform(
    source: String, destination: URL, fileManager: FileManager = .default
  ) throws {
    let resolvedSource = URL(fileURLWithPath: source).resolvingSymlinksInPath()
    let folder = destination.deletingLastPathComponent()
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    let temporary = folder.appendingPathComponent(temporaryPrefix + UUID().uuidString)
    do {
      try fileManager.copyItem(at: resolvedSource, to: temporary)
      switch InstallFileSystem.localKind(destination.path) {
      case .symbolicLink:
        try fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
      case .directory:
        _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
      default:
        try fileManager.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? fileManager.removeItem(at: temporary)
      throw error
    }
  }

  private static func offerKind(
    at destination: URL, sourceVersion: String, fileSystem: InstallFileSystem
  ) -> AppBundleCopyOffer.Kind? {
    switch fileSystem.kind(destination.path) {
    case nil: return .add
    case .symbolicLink: return .replaceLink
    case .directory:
      guard
        let installed = InstalledCopies.bundleVersion(destination.path, fileSystem: fileSystem),
        let installedParts = UpdateCheck.semverParts(installed),
        let sourceParts = UpdateCheck.semverParts(sourceVersion),
        installedParts.lexicographicallyPrecedes(sourceParts)
      else { return nil }
      return .update(from: installed)
    case .file: return nil
    }
  }
}
