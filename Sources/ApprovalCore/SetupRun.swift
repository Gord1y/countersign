import Foundation

public struct SetupPreview: Sendable, Equatable {
  public let text: String
  public let failures: [String]
  public let changedFiles: [URL]

  public init(text: String, failures: [String], changedFiles: [URL]) {
    self.text = text
    self.failures = failures
    self.changedFiles = changedFiles
  }

  public var hasChanges: Bool {
    !changedFiles.isEmpty
  }
}

public struct SetupRun {
  private let executablePath: String
  private let uninstall: Bool
  private let addsWaitingEntry: Bool
  private let addsContextEntry: Bool
  private let writesFiles: Bool
  private let codexHookTrustFile: URL?
  private let codexWaitingHookTrustFile: URL?
  private let now: () -> Date
  private let output: (String) -> Void
  private let confirm: (String) -> Bool
  public private(set) var failures: [String] = []
  public private(set) var changedFiles: [URL] = []

  public init(
    executablePath: String, uninstall: Bool, addsWaitingEntry: Bool,
    addsContextEntry: Bool = false, writesFiles: Bool = true,
    codexHookTrustFile: URL? = nil, codexWaitingHookTrustFile: URL? = nil,
    now: @escaping () -> Date = { Date() },
    output: @escaping (String) -> Void, confirm: @escaping (String) -> Bool
  ) {
    self.executablePath = executablePath
    self.uninstall = uninstall
    self.addsWaitingEntry = addsWaitingEntry
    self.addsContextEntry = addsContextEntry
    self.writesFiles = writesFiles
    self.codexHookTrustFile = codexHookTrustFile
    self.codexWaitingHookTrustFile = codexWaitingHookTrustFile
    self.now = now
    self.output = output
    self.confirm = confirm
  }

  public static func preview(
    _ location: HookConfigLocation, executablePath: String, uninstall: Bool,
    addsWaitingEntry: Bool, addsContextEntry: Bool = false
  ) -> SetupPreview {
    var text = ""
    var run = SetupRun(
      executablePath: executablePath, uninstall: uninstall, addsWaitingEntry: addsWaitingEntry,
      addsContextEntry: addsContextEntry, writesFiles: false,
      output: { text += $0 }, confirm: { _ in true })
    _ = run.apply(location)
    return SetupPreview(text: text, failures: run.failures, changedFiles: run.changedFiles)
  }

  public mutating func apply(_ location: HookConfigLocation) -> Bool {
    let file = location.file
    let updated: [UInt8]?
    do {
      let original = try ConfigFileStore.read(file)
      updated =
        uninstall
        ? try HookSetup.uninstall(from: original, host: location.host)
        : try HookSetup.install(
          into: original, host: location.host, executablePath: executablePath,
          addsWaitingEntry: addsWaitingEntry, addsContextEntry: addsContextEntry)
      guard try offer(updated, replacing: original, in: file) else { return true }
    } catch {
      report(error, in: file)
      return false
    }
    if location.host == .codex, writesFiles {
      let written = uninstall ? nil : updated
      if let codexHookTrustFile {
        CodexHookTrust.recordWritten(written, at: location, in: codexHookTrustFile)
      }
      if let codexWaitingHookTrustFile {
        CodexHookTrust.recordWrittenWaiting(written, at: location, in: codexWaitingHookTrustFile)
      }
    }
    return true
  }

  private mutating func offer(_ updated: [UInt8]?, replacing original: [UInt8]?, in file: URL)
    throws -> Bool
  {
    let path = file.path
    guard let updated, updated != original else {
      say("\(path): already up to date")
      return false
    }
    say(path)
    output(
      UnifiedDiff.render(
        old: String(decoding: original ?? [], as: UTF8.self),
        new: String(decoding: updated, as: UTF8.self),
        oldLabel: original == nil ? "/dev/null" : path, newLabel: path))
    guard writesFiles else {
      changedFiles.append(file)
      return true
    }
    guard confirm(path) else { return false }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let backup = try ConfigFileStore.write(updated, to: file, date: now(), backingUp: true) {
      say("\(path): backup at \(backup.path)")
    }
    say("\(path): updated")
    changedFiles.append(file)
    return true
  }

  private func say(_ line: String) {
    output(line + "\n")
  }

  private mutating func report(_ error: any Error, in file: URL) {
    let line = "\(file.path): error: \(Self.describe(error))"
    failures.append(line)
    say(line)
  }

  public static func describe(_ error: any Error) -> String {
    switch error {
    case let error as JSONSpanError: return error.description
    case let error as HookSetupError: return error.description
    case let error as RuleEditError: return error.description
    default: return error.localizedDescription
    }
  }
}
