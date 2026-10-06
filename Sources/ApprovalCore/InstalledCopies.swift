import Foundation

enum InstallFileKind: Sendable, Equatable {
  case file
  case directory
  case symbolicLink
}

public struct InstallFileSystem: Sendable {
  let kind: @Sendable (String) -> InstallFileKind?
  let resolved: @Sendable (String) -> String?
  let contents: @Sendable (String) -> Data?

  public static let local = InstallFileSystem(
    kind: localKind, resolved: localResolved, contents: { FileManager.default.contents(atPath: $0) }
  )

  static func localKind(_ path: String) -> InstallFileKind? {
    guard
      let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type]
        as? FileAttributeType
    else { return nil }
    switch type {
    case .typeRegular: return .file
    case .typeDirectory: return .directory
    case .typeSymbolicLink: return .symbolicLink
    default: return nil
    }
  }

  static func localResolved(_ path: String) -> String? {
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
  }
}

enum InstallSource: Sendable, Equatable {
  case homebrew(prefix: String)
  case installer
  case app

  var name: String {
    switch self {
    case .homebrew: return "Homebrew"
    case .installer: return "Installer"
    case .app: return InstalledCopies.appBundle
    }
  }

  var isHomebrew: Bool {
    guard case .homebrew = self else { return false }
    return true
  }
}

enum InstallRemoval: Sendable, Equatable {
  case brewUninstall(prefix: String)
  case remove(String)
  case removeDirectory(String)
}

struct InstalledCopy: Sendable, Equatable {
  let source: InstallSource
  let appVersion: String?
  let cliVersion: String?
  let paths: [String]
  let executables: [String]
  let removals: [InstallRemoval]
  let hasApp: Bool
  let cliPath: String?
  let appCopyVersion: String?

  var version: String? {
    appVersion ?? cliVersion
  }

  var label: String {
    source.name + " " + (version ?? "(version unknown)")
  }
}

public struct DuplicateInstallEntry: Sendable, Equatable {
  public let label: String
  public let version: String?
  public let paths: [String]
  public let isCalledByHooks: Bool
  public let isRunning: Bool
  public let isNewest: Bool
  public let hasApp: Bool
  public let removalCommand: String
  public let setupCommand: String?

  var summary: String {
    "\(label): \(paths.joined(separator: ", "))"
      + Self.parenthesized(markers(calledByHooks: "called by the hooks"))
  }

  var promptLine: String {
    "- \(label): \(paths.joined(separator: ", "))"
      + Self.parenthesized(markers(calledByHooks: "the hooks call this one"))
  }

  private func markers(calledByHooks: String) -> [String] {
    var markers: [String] = []
    if isCalledByHooks {
      markers.append(calledByHooks)
    }
    if isRunning {
      markers.append("running now")
    }
    if isNewest {
      markers.append("newest")
    }
    return markers
  }

  private static func parenthesized(_ markers: [String]) -> String {
    markers.isEmpty ? "" : " (\(markers.joined(separator: ", ")))"
  }
}

public struct DuplicateInstallStep: Sendable, Equatable {
  public let text: String
  public let command: String?
}

public struct DuplicateInstall: Sendable, Equatable {
  static let check = "copies"
  static let background =
    "https://github.com/Gord1y/countersign/blob/main/docs/troubleshooting.md#two-copies-of-countersign-are-installed"

  public static let question = "Which one do you want to keep?"
  public static let explanation =
    "Each copy updates on its own, so the terminal and the hooks can run different versions."

  public let entries: [DuplicateInstallEntry]

  public var title: String {
    "\(Self.countWord(entries.count)) copies of Countersign are installed"
  }

  public var hooksCallNone: Bool {
    !entries.contains(where: \.isCalledByHooks)
  }

  public var suggestedIndex: Int {
    let newest = entries.indices.filter { entries[$0].isNewest }
    var remaining = newest.isEmpty ? Array(entries.indices) : newest
    let preferences: [KeyPath<DuplicateInstallEntry, Bool>] = [
      \.isCalledByHooks, \.hasApp, \.isRunning,
    ]
    for preference in preferences {
      let preferred = remaining.filter { entries[$0][keyPath: preference] }
      if !preferred.isEmpty {
        remaining = preferred
      }
    }
    return remaining.first ?? 0
  }

  public func steps(keeping index: Int) -> [DuplicateInstallStep] {
    guard entries.indices.contains(index) else { return [] }
    let kept = entries[index]
    let removal = entries.indices.filter { $0 != index }.map { entries[$0].removalCommand }
      .joined(separator: " && ")
    guard let setupCommand = kept.setupCommand else {
      var steps = [DuplicateInstallStep(text: "Remove \(others):", command: removal)]
      if !kept.isCalledByHooks, let app = kept.paths.first {
        steps.append(
          DuplicateInstallStep(
            text:
              "Then open \(app) and click Update on each agent under Agents, so the hooks call this copy.",
            command: nil))
      }
      return steps
    }
    guard kept.isCalledByHooks else {
      return [
        DuplicateInstallStep(text: "Point your agents' hooks at it:", command: setupCommand),
        DuplicateInstallStep(text: "Then remove \(others):", command: removal),
      ]
    }
    return [DuplicateInstallStep(text: "Remove \(others):", command: removal)]
  }

  public var agentPrompt: String {
    var lines = [
      "I have \(Self.countWord(entries.count).lowercased()) copies of Countersign installed (a macOS approval panel for AI coding agents):"
    ]
    lines.append(contentsOf: entries.map(\.promptLine))
    lines.append(
      "Each copy updates on its own, and my agents' hooks call \(hooksCalled). Help me choose which one to keep: explain the options and their trade-offs, then give me the exact commands. Don't delete or change anything without asking me first."
    )
    lines.append("Background: \(Self.background)")
    return lines.joined(separator: "\n")
  }

  public var doctorLine: DoctorLine {
    var parts = ["\(entries.count) copies of Countersign are installed"]
    parts.append(contentsOf: entries.map(\.summary))
    if hooksCallNone {
      parts.append("the hooks call none of them")
    }
    parts.append("keep the one you want and remove \(others)")
    let each = entries.map { "\($0.label): \($0.removalCommand)" }
    parts.append("the command that removes each: \(each.joined(separator: ", "))")
    parts.append("countersign settings shows the steps for the copy you pick")
    return DoctorLine(status: .warn, check: Self.check, detail: parts.joined(separator: "; "))
  }

  private var hooksCalled: String {
    switch entries.filter(\.isCalledByHooks).count {
    case 0: return "none of them"
    case 1: return "only one of them"
    default: return "more than one of them"
    }
  }

  private var others: String {
    entries.count > 2 ? "the others" : "the other"
  }

  static func countWord(_ count: Int) -> String {
    switch count {
    case 2: return "Two"
    case 3: return "Three"
    case 4: return "Four"
    default: return String(count)
    }
  }
}

public struct InstallVersionMismatch: Sendable, Equatable {
  static let check = "versions"
  static let appUpdateCommand =
    "curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | COUNTERSIGN_APP=1 sh"

  public let appVersion: String
  public let cliVersion: String
  public let appIsOlder: Bool
  let isHomebrewCopy: Bool

  init?(appVersion: String, cliVersion: String) {
    guard let app = UpdateCheck.semverParts(appVersion),
      let cli = UpdateCheck.semverParts(cliVersion), app != cli
    else { return nil }
    self.appVersion = appVersion
    self.cliVersion = cliVersion
    appIsOlder = app.lexicographicallyPrecedes(cli)
    isHomebrewCopy = false
  }

  init?(homebrewCopyVersion: String, kegAppVersion: String) {
    guard let copy = InstalledCopies.orderedVersion(homebrewCopyVersion),
      let keg = InstalledCopies.orderedVersion(kegAppVersion), copy.lexicographicallyPrecedes(keg)
    else { return nil }
    appVersion = homebrewCopyVersion
    cliVersion = kegAppVersion
    appIsOlder = true
    isHomebrewCopy = true
  }

  public var title: String {
    if isHomebrewCopy {
      return "The copy of Countersign.app in ~/Applications is older than Homebrew's"
    }
    return appIsOlder
      ? "The menu-bar app is older than the command-line tool"
      : "The command-line tool is older than the menu-bar app"
  }

  public var advice: String {
    if isHomebrewCopy {
      return
        "Countersign.app in ~/Applications is \(appVersion) but Homebrew installed \(cliVersion). The menu-bar app updates its copy when it starts; to update it now, open Settings ▸ App:"
    }
    return appIsOlder
      ? "Countersign.app is \(appVersion) but countersign is \(cliVersion). Update the app:"
      : "countersign is \(cliVersion) but Countersign.app is \(appVersion), and your agents' hooks run countersign. Update it:"
  }

  public var command: String {
    if isHomebrewCopy { return "countersign settings" }
    return appIsOlder ? Self.appUpdateCommand : UpdateCommand.curlInstallCommand
  }

  public var doctorLine: DoctorLine {
    DoctorLine(
      status: .warn, check: Self.check,
      detail: title.prefix(1).lowercased() + title.dropFirst() + ": \(advice) \(command)")
  }
}

public enum InstalledCopies {
  public static let homebrewPrefixes = ["/opt/homebrew", "/usr/local"]
  static let appBundle = "Countersign.app"
  static let bundleExecutable = "/Contents/MacOS/" + HookCommand.executableName
  static let bundleInfo = "/Contents/Info.plist"
  static let cellarDirectory = "/Cellar/" + HookCommand.executableName
  static let installerCLI = ".local/bin/" + HookCommand.executableName
  static let userApplications = "Applications/" + appBundle
  static let systemApplications = "/Applications/" + appBundle

  public static func duplicates(
    home: URL, root: URL, fileSystem: InstallFileSystem, cliVersion: (String) -> String?,
    hookExecutables: [String], runningExecutable: String?
  ) -> DuplicateInstall? {
    let copies = detect(home: home, root: root, fileSystem: fileSystem, cliVersion: cliVersion)
    return duplicates(
      of: copies, hookExecutables: hookExecutables, runningExecutable: runningExecutable,
      home: home, root: root, fileSystem: fileSystem)
  }

  public static func versionMismatch(
    home: URL, root: URL, fileSystem: InstallFileSystem, cliVersion: (String) -> String?
  ) -> InstallVersionMismatch? {
    let copies = detect(home: home, root: root, fileSystem: fileSystem, cliVersion: cliVersion)
    if let installer = copies.first(where: { $0.source == .installer }), installer.hasApp,
      let appVersion = installer.appVersion, let cliVersion = installer.cliVersion
    {
      return InstallVersionMismatch(appVersion: appVersion, cliVersion: cliVersion)
    }
    for homebrew in copies where homebrew.source.isHomebrew {
      guard let copyVersion = homebrew.appCopyVersion, let keg = homebrew.paths.dropFirst().first,
        let kegAppVersion = bundleVersion(keg + "/" + appBundle, fileSystem: fileSystem)
      else { continue }
      if let mismatch = InstallVersionMismatch(
        homebrewCopyVersion: copyVersion, kegAppVersion: kegAppVersion)
      {
        return mismatch
      }
    }
    return nil
  }

  public static func version(fromVersionOutput output: String) -> String? {
    let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = HookCommand.executableName + " "
    guard line.hasPrefix(prefix) else { return nil }
    let version = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    guard !version.isEmpty, !version.contains(where: \.isWhitespace) else { return nil }
    return version
  }

  static func detect(
    home: URL, root: URL, fileSystem: InstallFileSystem, cliVersion: (String) -> String?
  ) -> [InstalledCopy] {
    var scan = InstallScan(home: home, root: root, fileSystem: fileSystem)
    var copies = homebrewPrefixes.compactMap { scan.homebrew(prefix: $0) }
    if let installer = scan.installer(cliVersion: cliVersion) {
      copies.append(installer)
    }
    if let app = scan.app(at: scan.system(systemApplications)) {
      copies.append(app)
    }
    if let app = scan.app(at: scan.inHome(userApplications)) {
      copies.append(app)
    }
    return copies
  }

  static func duplicates(
    of copies: [InstalledCopy], hookExecutables: [String], runningExecutable: String?,
    home: URL, root: URL, fileSystem: InstallFileSystem
  ) -> DuplicateInstall? {
    guard copies.count > 1 else { return nil }
    let index = { (path: String) -> Int? in
      let resolved = fileSystem.resolved(path) ?? path
      return copies.firstIndex { $0.executables.contains(resolved) }
    }
    let called = Set(hookExecutables.compactMap(index))
    let running = runningExecutable.flatMap(index)
    let known = copies.compactMap { orderedVersion($0.version) }
    let differ = known.count > 1 && known.contains { $0 != known.first }
    let newest = differ ? known.max { $0.lexicographicallyPrecedes($1) } : nil
    let qualifiesBrew = copies.filter(\.source.isHomebrew).count > 1
    let entries = copies.enumerated().map { offset, copy in
      DuplicateInstallEntry(
        label: copy.label,
        version: copy.version,
        paths: copy.paths.map { shown($0, home: home, root: root) },
        isCalledByHooks: called.contains(offset),
        isRunning: running == offset,
        isNewest: newest != nil && orderedVersion(copy.version) == newest,
        hasApp: copy.hasApp,
        removalCommand: copy.removals.map {
          command(for: $0, qualifiesBrew: qualifiesBrew, home: home, root: root)
        }.joined(separator: " && "),
        setupCommand: copy.cliPath.map {
          shellPath(shown($0, home: home, root: root)) + " setup --cli --yes"
        })
    }
    return DuplicateInstall(entries: entries)
  }

  static func orderedVersion(_ version: String?) -> [Int]? {
    guard let version else { return nil }
    if let underscore = version.lastIndex(of: "_") {
      let revision = version[version.index(after: underscore)...]
      if !revision.isEmpty, revision.allSatisfy({ $0.isASCII && $0.isNumber }) {
        return UpdateCheck.semverParts(String(version[..<underscore]))
      }
    }
    return UpdateCheck.semverParts(version)
  }

  static func command(for removal: InstallRemoval, qualifiesBrew: Bool, home: URL, root: URL)
    -> String
  {
    switch removal {
    case .brewUninstall(let prefix):
      let brew = qualifiesBrew ? shellPath(prefix + "/bin/brew") : "brew"
      return "\(brew) uninstall \(HookCommand.executableName)"
    case .remove(let path):
      return "rm " + shellPath(shown(path, home: home, root: root))
    case .removeDirectory(let path):
      return "rm -rf " + shellPath(shown(path, home: home, root: root))
    }
  }

  static func shown(_ path: String, home: URL, root: URL) -> String {
    let rootPath = trimmed(root.standardizedFileURL.path)
    if !rootPath.isEmpty, path.hasPrefix(rootPath + "/") {
      return String(path.dropFirst(rootPath.count))
    }
    return HomePath.abbreviating(path, relativeTo: home)
  }

  static func shellPath(_ path: String) -> String {
    let homePrefix = "~/"
    guard path.hasPrefix(homePrefix) else { return HookCommand.shellWord(path) }
    return homePrefix + HookCommand.shellWord(String(path.dropFirst(homePrefix.count)))
  }

  static func kegVersion(_ keg: String) -> String? {
    let url = URL(fileURLWithPath: keg)
    guard url.deletingLastPathComponent().path.hasSuffix(cellarDirectory) else { return nil }
    return url.lastPathComponent
  }

  static func bundleVersion(_ app: String, fileSystem: InstallFileSystem) -> String? {
    guard let data = fileSystem.contents(app + bundleInfo),
      let info = try? PropertyListDecoder().decode(BundleInfo.self, from: data),
      let version = info.shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
      !version.isEmpty
    else { return nil }
    return version
  }

  static func trimmed(_ path: String) -> String {
    path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}

private struct BundleInfo: Decodable {
  let shortVersion: String?

  enum CodingKeys: String, CodingKey {
    case shortVersion = "CFBundleShortVersionString"
  }
}

private struct InstallScan {
  let home: URL
  let root: URL
  let fileSystem: InstallFileSystem
  private var claimed: [String] = []

  init(home: URL, root: URL, fileSystem: InstallFileSystem) {
    self.home = home
    self.root = root
    self.fileSystem = fileSystem
  }

  func system(_ path: String) -> String {
    InstalledCopies.trimmed(root.standardizedFileURL.path) + path
  }

  func inHome(_ relative: String) -> String {
    home.appendingPathComponent(relative).path
  }

  mutating func homebrew(prefix: String) -> InstalledCopy? {
    let binary = system(prefix + "/bin/" + HookCommand.executableName)
    guard let resolvedBinary = fileSystem.resolved(binary),
      fileSystem.kind(resolvedBinary) == .file, claim(resolvedBinary)
    else { return nil }
    var paths = [binary]
    var executables = [resolvedBinary]
    var removals: [InstallRemoval] = [.brewUninstall(prefix: prefix)]
    var hasApp = false
    var appCopyVersion: String?
    let keg = fileSystem.resolved(system(prefix + "/opt/" + HookCommand.executableName))
    if let keg {
      claimed.append(keg)
      paths.append(keg)
      let kegApp = keg + "/" + InstalledCopies.appBundle
      hasApp = fileSystem.kind(kegApp) == .directory
      if let kegExecutable = fileSystem.resolved(kegApp + InstalledCopies.bundleExecutable) {
        executables.append(kegExecutable)
      }
      let link = inHome(InstalledCopies.userApplications)
      if fileSystem.kind(link) == .symbolicLink, let target = fileSystem.resolved(link),
        target.hasPrefix(keg + "/")
      {
        paths.append(link)
        removals.append(.remove(link))
      } else if let copyVersion = ownCopyVersion(link, kegApp: kegApp) {
        paths.append(link)
        executables.append(contentsOf: appExecutables(link))
        removals.append(.removeDirectory(link))
        appCopyVersion = copyVersion
      }
    }
    let version = keg.flatMap(InstalledCopies.kegVersion)
    return InstalledCopy(
      source: .homebrew(prefix: prefix), appVersion: hasApp ? version : nil, cliVersion: version,
      paths: paths, executables: executables, removals: removals, hasApp: hasApp,
      cliPath: binary, appCopyVersion: appCopyVersion)
  }

  private mutating func ownCopyVersion(_ copy: String, kegApp: String) -> String? {
    guard fileSystem.kind(copy) == .directory,
      fileSystem.kind(inHome(InstalledCopies.installerCLI)) != .file,
      let kegVersion = bundleVersion(kegApp).flatMap(InstalledCopies.orderedVersion),
      let copyVersion = bundleVersion(copy),
      let ordered = InstalledCopies.orderedVersion(copyVersion),
      !kegVersion.lexicographicallyPrecedes(ordered),
      let resolved = fileSystem.resolved(copy), claim(resolved)
    else { return nil }
    return copyVersion
  }

  mutating func installer(cliVersion: (String) -> String?) -> InstalledCopy? {
    let cli = inHome(InstalledCopies.installerCLI)
    guard fileSystem.kind(cli) == .file, let resolvedCLI = fileSystem.resolved(cli),
      claim(resolvedCLI)
    else { return nil }
    var paths = [cli]
    var executables = [resolvedCLI]
    var removals: [InstallRemoval] = [.remove(cli)]
    var hasApp = false
    var appVersion: String?
    let app = inHome(InstalledCopies.userApplications)
    if fileSystem.kind(app) == .directory, let resolvedApp = fileSystem.resolved(app),
      claim(resolvedApp)
    {
      paths.append(app)
      executables.append(contentsOf: appExecutables(app))
      removals.append(.removeDirectory(app))
      hasApp = true
      appVersion = bundleVersion(app)
    }
    return InstalledCopy(
      source: .installer, appVersion: appVersion, cliVersion: cliVersion(cli), paths: paths,
      executables: executables, removals: removals, hasApp: hasApp, cliPath: cli,
      appCopyVersion: nil)
  }

  mutating func app(at path: String) -> InstalledCopy? {
    guard fileSystem.kind(path) == .directory, let resolved = fileSystem.resolved(path),
      claim(resolved)
    else { return nil }
    return InstalledCopy(
      source: .app, appVersion: bundleVersion(path), cliVersion: nil, paths: [path],
      executables: appExecutables(path), removals: [.removeDirectory(path)], hasApp: true,
      cliPath: nil, appCopyVersion: nil)
  }

  private func appExecutables(_ app: String) -> [String] {
    fileSystem.resolved(app + InstalledCopies.bundleExecutable).map { [$0] } ?? []
  }

  private func bundleVersion(_ app: String) -> String? {
    InstalledCopies.bundleVersion(app, fileSystem: fileSystem)
  }

  private mutating func claim(_ path: String) -> Bool {
    guard !claimed.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
      return false
    }
    claimed.append(path)
    return true
  }
}
