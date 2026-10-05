import Foundation

public enum ContextHookStatus: Sendable, Equatable {
  case notWired
  case wired
  case needsUpdate
  case unusable(String)

  public var title: String {
    switch self {
    case .notWired: return "Not wired"
    case .wired: return "Wired"
    case .needsUpdate: return "Needs an update"
    case .unusable: return "Can't be set up"
    }
  }
}

public enum ContextHookRun {
  private struct Change {
    let original: [UInt8]?
    let updated: [UInt8]
  }

  public static func status(file: URL, executablePath: String) -> ContextHookStatus {
    do {
      let original = try ConfigFileStore.read(file)
      let installed = try ContextHookSetup.install(into: original, executablePath: executablePath)
      guard let original, !ContextHookSetup.entries(in: original).isEmpty else {
        return .notWired
      }
      return installed == original ? .wired : .needsUpdate
    } catch {
      return .unusable(SetupRun.describe(error))
    }
  }

  public static func preview(file: URL, executablePath: String, enable: Bool) -> SetupPreview {
    let change: Change?
    do {
      change = try pendingChange(file: file, executablePath: executablePath, enable: enable)
    } catch {
      let line = errorLine(error, in: file)
      return SetupPreview(text: line + "\n", failures: [line], changedFiles: [])
    }
    guard let change else {
      return SetupPreview(
        text: "\(file.path): already up to date\n", failures: [], changedFiles: [])
    }
    let text =
      file.path + "\n"
      + UnifiedDiff.render(
        old: String(decoding: change.original ?? [], as: UTF8.self),
        new: String(decoding: change.updated, as: UTF8.self),
        oldLabel: change.original == nil ? "/dev/null" : file.path, newLabel: file.path)
    return SetupPreview(text: text, failures: [], changedFiles: [file])
  }

  public static func apply(
    file: URL, executablePath: String, enable: Bool, now: Date
  ) -> String? {
    do {
      guard
        let change = try pendingChange(
          file: file, executablePath: executablePath, enable: enable)
      else { return nil }
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      _ = try ConfigFileStore.write(change.updated, to: file, date: now, backingUp: true)
      return nil
    } catch {
      return errorLine(error, in: file)
    }
  }

  private static func pendingChange(file: URL, executablePath: String, enable: Bool) throws
    -> Change?
  {
    let original = try ConfigFileStore.read(file)
    let updated: [UInt8]?
    if enable {
      updated = try ContextHookSetup.install(into: original, executablePath: executablePath)
    } else {
      updated = try ContextHookSetup.uninstall(from: original)
    }
    guard let updated, updated != original else { return nil }
    return Change(original: original, updated: updated)
  }

  private static func errorLine(_ error: any Error, in file: URL) -> String {
    "\(file.path): error: \(SetupRun.describe(error))"
  }
}
