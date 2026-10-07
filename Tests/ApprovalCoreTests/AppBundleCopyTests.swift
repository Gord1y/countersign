import Foundation
import Testing

@testable import ApprovalCore

private let home = URL(fileURLWithPath: "/Users/dev")
private let destinationPath = "/Users/dev/Applications/Countersign.app"
private let tarballBinary = "/Users/dev/Downloads/countersign-0.3.0/bin/countersign"
private let tarballApp = "/Users/dev/Downloads/countersign-0.3.0/Countersign.app"
private let bottleBinary = "/opt/homebrew/Cellar/countersign/0.3.0/bin/countersign"
private let bottleApp = "/opt/homebrew/Cellar/countersign/0.3.0/Countersign.app"
private let optApp = "/opt/homebrew/opt/countersign/Countersign.app"
private let intelOptApp = "/usr/local/opt/countersign/Countersign.app"

private enum Node {
  case directory(version: String?)
  case file
  case link(to: String?)
}

private func memoryFileSystem(_ nodes: [String: Node]) -> InstallFileSystem {
  let infoSuffix = "/Contents/Info.plist"
  let resolve: @Sendable (String) -> String? = { path in
    switch nodes[path] {
    case nil: return nil
    case .link(let target)?: return target.flatMap { nodes[$0] == nil ? nil : $0 }
    default: return path
    }
  }
  return InstallFileSystem(
    kind: { path in
      switch nodes[path] {
      case .directory?: return .directory
      case .file?: return .file
      case .link?: return .symbolicLink
      case nil: return nil
      }
    },
    resolved: resolve,
    contents: { path in
      guard path.hasSuffix(infoSuffix),
        let app = resolve(String(path.dropLast(infoSuffix.count))),
        case .directory(let version?)? = nodes[app]
      else { return nil }
      return try? PropertyListEncoder().encode(["CFBundleShortVersionString": version])
    })
}

private func bundleOffer(_ nodes: [String: Node], binary: String = bottleBinary)
  -> AppBundleCopyOffer?
{
  AppBundleCopy.offer(
    resolvedExecutable: binary, home: home, fileSystem: memoryFileSystem(nodes))
}

private struct CopyLayout {
  let base: URL

  var destination: URL { base.appendingPathComponent("home/Applications/Countersign.app") }
  var source: String { base.appendingPathComponent("brew/Countersign.app").path }

  init() throws {
    let created = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
    base = URL(fileURLWithPath: created.path).resolvingSymlinksInPath()
  }

  func remove() {
    try? FileManager.default.removeItem(at: base)
  }

  func bundle(at path: String, version: String) throws {
    let contents = URL(fileURLWithPath: path).appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = try PropertyListEncoder().encode(["CFBundleShortVersionString": version])
    try plist.write(to: contents.appendingPathComponent("Info.plist"))
  }

  func version(at url: URL) -> String? {
    InstalledCopies.bundleVersion(url.path, fileSystem: .local)
  }

  func leftovers() -> [String] {
    let names =
      (try? FileManager.default.contentsOfDirectory(
        atPath: destination.deletingLastPathComponent().path)) ?? []
    return names.filter { $0.hasPrefix(".Countersign.app.copying-") }
  }
}

@Suite struct AppBundleCopyTests {
  @Test func looksNextToTheBinaryAndNamesHomebrewsStablePath() {
    #expect(AppBundleCopy.candidate(forResolvedExecutable: tarballBinary) == tarballApp)
    #expect(AppBundleCopy.candidate(forResolvedExecutable: bottleBinary) == bottleApp)
    #expect(AppBundleCopy.stableSource(for: bottleApp) == optApp)
    #expect(
      AppBundleCopy.stableSource(for: "/usr/local/Cellar/countersign/0.2.0_1/Countersign.app")
        == intelOptApp)
    #expect(AppBundleCopy.stableSource(for: tarballApp) == tarballApp)
    #expect(AppBundleCopy.destination(home: home).path == destinationPath)
  }

  @Test func offersToAddWhenNothingIsAtTheDestination() {
    #expect(
      bundleOffer([bottleApp: .directory(version: "0.3.0")])
        == AppBundleCopyOffer(
          kind: .add, source: optApp, destination: URL(fileURLWithPath: destinationPath),
          version: "0.3.0"))
    #expect(
      bundleOffer([tarballApp: .directory(version: "0.3.0")], binary: tarballBinary)?.source
        == tarballApp)
  }

  @Test func offersToReplaceALinkWhereverItPoints() {
    let bundle = [bottleApp: Node.directory(version: "0.3.0")]
    #expect(
      bundleOffer(
        bundle.merging([destinationPath: .link(to: optApp), optApp: .directory(version: "0.3.0")]) {
          $1
        })?
        .kind == .replaceLink)
    #expect(
      bundleOffer(bundle.merging([destinationPath: .link(to: "/gone/Countersign.app")]) { $1 })?
        .kind == .replaceLink)
  }

  @Test func offersToUpdateAnOlderBundle() {
    let offer = bundleOffer([
      bottleApp: .directory(version: "0.3.0"), destinationPath: .directory(version: "0.2.0"),
    ])
    #expect(offer?.kind == .update(from: "0.2.0"))
    #expect(offer?.version == "0.3.0")
  }

  @Test func offersNothingWhenThereIsNothingToImprove() {
    let source = [bottleApp: Node.directory(version: "0.3.0")]
    for destination: Node in [
      .directory(version: "0.3.0"), .directory(version: "0.4.0"), .directory(version: nil),
      .directory(version: "dev"), .file,
    ] {
      #expect(bundleOffer(source.merging([destinationPath: destination]) { $1 }) == nil)
    }
    #expect(bundleOffer([:]) == nil)
    #expect(bundleOffer([bottleApp: .directory(version: nil)]) == nil)
    #expect(bundleOffer([bottleApp: .file]) == nil)
  }

  @Test func refreshesACopyThatHomebrewHasOutgrown() {
    let copy = [destinationPath: Node.directory(version: "0.3.0")]
    let newer = copy.merging([optApp: .directory(version: "0.3.1")]) { $1 }
    let expected = AppBundleCopyRefresh(
      source: optApp, destination: URL(fileURLWithPath: destinationPath), from: "0.3.0",
      to: "0.3.1")
    #expect(
      AppBundleCopy.refresh(
        runningBundle: destinationPath, home: home, fileSystem: memoryFileSystem(newer))
        == expected)
    #expect(
      AppBundleCopy.refresh(
        runningBundle: destinationPath + "/", home: home, fileSystem: memoryFileSystem(newer))
        == expected)
    #expect(
      AppBundleCopy.refresh(
        runningBundle: "/Applications/Countersign.app", home: home,
        fileSystem: memoryFileSystem(newer)) == nil)
    #expect(
      AppBundleCopy.refresh(
        runningBundle: destinationPath, home: home,
        fileSystem: memoryFileSystem([
          destinationPath: .link(to: optApp), optApp: .directory(version: "0.3.1"),
        ])) == nil)
    for homebrew: String in ["0.3.0", "0.2.0"] {
      #expect(
        AppBundleCopy.refresh(
          runningBundle: destinationPath, home: home,
          fileSystem: memoryFileSystem(copy.merging([optApp: .directory(version: homebrew)]) { $1 })
        )
          == nil)
    }
  }

  @Test func refreshFallsBackToTheIntelPrefix() {
    let nodes: [String: Node] = [
      destinationPath: .directory(version: "0.3.0"), intelOptApp: .directory(version: "0.3.1"),
    ]
    #expect(
      AppBundleCopy.refresh(
        runningBundle: destinationPath, home: home, fileSystem: memoryFileSystem(nodes))?.source
        == intelOptApp)
  }

  @Test func copiesIntoAFolderThatDoesNotExistYet() throws {
    let layout = try CopyLayout()
    defer { layout.remove() }
    try layout.bundle(at: layout.source, version: "0.3.0")
    try AppBundleCopy.perform(source: layout.source, destination: layout.destination)
    #expect(layout.version(at: layout.destination) == "0.3.0")
    #expect(layout.leftovers().isEmpty)
  }

  @Test func replacesALinkWithoutTouchingItsTarget() throws {
    let layout = try CopyLayout()
    defer { layout.remove() }
    let target = layout.base.appendingPathComponent("target/Countersign.app").path
    try layout.bundle(at: layout.source, version: "0.3.0")
    try layout.bundle(at: target, version: "0.2.0")
    try FileManager.default.createDirectory(
      at: layout.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: layout.destination.path, withDestinationPath: target)
    try AppBundleCopy.perform(source: layout.source, destination: layout.destination)
    #expect(InstallFileSystem.localKind(layout.destination.path) == .directory)
    #expect(layout.version(at: layout.destination) == "0.3.0")
    #expect(layout.version(at: URL(fileURLWithPath: target)) == "0.2.0")
    #expect(layout.leftovers().isEmpty)
  }

  @Test func replacesAnOlderBundleThroughALinkedSource() throws {
    let layout = try CopyLayout()
    defer { layout.remove() }
    try layout.bundle(at: layout.source, version: "0.3.0")
    let linkedSource = layout.base.appendingPathComponent("opt/Countersign.app")
    try FileManager.default.createDirectory(
      at: linkedSource.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: linkedSource.path, withDestinationPath: layout.source)
    try layout.bundle(at: layout.destination.path, version: "0.2.0")
    try AppBundleCopy.perform(source: linkedSource.path, destination: layout.destination)
    #expect(InstallFileSystem.localKind(layout.destination.path) == .directory)
    #expect(layout.version(at: layout.destination) == "0.3.0")
    #expect(layout.leftovers().isEmpty)
  }

  @Test func readsABundleVersionTrimmedAndNilWhenEmptyOrMissing() {
    let versions: [String: Node] = [
      "/a.app": .directory(version: " 1.2.3\n"), "/b.app": .directory(version: "  "),
      "/c.app": .directory(version: nil),
    ]
    let fileSystem = memoryFileSystem(versions)
    #expect(InstalledCopies.bundleVersion("/a.app", fileSystem: fileSystem) == "1.2.3")
    #expect(InstalledCopies.bundleVersion("/b.app", fileSystem: fileSystem) == nil)
    #expect(InstalledCopies.bundleVersion("/c.app", fileSystem: fileSystem) == nil)
    #expect(InstalledCopies.bundleVersion("/missing.app", fileSystem: fileSystem) == nil)
  }
}
