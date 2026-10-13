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

  public static func status(location: HookConfigLocation, executablePath: String)
    -> ContextHookStatus
  {
    do {
      let original = try ConfigFileStore.read(location.file)
      let installed = try ContextHookSetup.install(
        into: original, executablePath: executablePath, host: location.host)
      guard let original, !ContextHookSetup.entries(in: original).isEmpty else {
        return .notWired
      }
      return installed == original ? .wired : .needsUpdate
    } catch {
      return .unusable(SetupRun.describe(error))
    }
  }

  public static func preview(
    locations: [HookConfigLocation], executablePath: String, enable: Bool
  ) -> SetupPreview {
    var text = ""
    var failures: [String] = []
    var changedFiles: [URL] = []
    for location in locations {
      let file = location.file
      do {
        guard
          let change = try pendingChange(
            location: location, executablePath: executablePath, enable: enable)
        else {
          text += "\(file.path): already up to date\n"
          continue
        }
        text +=
          file.path + "\n"
          + UnifiedDiff.render(
            old: String(decoding: change.original ?? [], as: UTF8.self),
            new: String(decoding: change.updated, as: UTF8.self),
            oldLabel: change.original == nil ? "/dev/null" : file.path, newLabel: file.path)
        changedFiles.append(file)
      } catch {
        let line = errorLine(error, in: file)
        text += line + "\n"
        failures.append(line)
      }
    }
    return SetupPreview(text: text, failures: failures, changedFiles: changedFiles)
  }

  public static func apply(
    locations: [HookConfigLocation], executablePath: String, enable: Bool, now: Date,
    codexPromptTrustFile: URL? = nil, codexToolTrustFile: URL? = nil
  ) -> [String] {
    var failures: [String] = []
    for location in locations {
      let file = location.file
      do {
        guard
          let change = try pendingChange(
            location: location, executablePath: executablePath, enable: enable)
        else { continue }
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try ConfigFileStore.write(change.updated, to: file, date: now, backingUp: true)
        if location.host == .codex, let codexPromptTrustFile, let codexToolTrustFile {
          CodexHookTrust.recordWrittenContext(
            change.updated, replacing: change.original, at: location,
            promptRecordFile: codexPromptTrustFile, toolRecordFile: codexToolTrustFile)
        }
      } catch {
        failures.append(errorLine(error, in: file))
      }
    }
    return failures
  }

  private static func pendingChange(
    location: HookConfigLocation, executablePath: String, enable: Bool
  ) throws -> Change? {
    let original = try ConfigFileStore.read(location.file)
    let updated: [UInt8]?
    if enable {
      updated = try ContextHookSetup.install(
        into: original, executablePath: executablePath, host: location.host)
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
