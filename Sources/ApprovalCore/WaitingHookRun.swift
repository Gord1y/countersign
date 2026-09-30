import Foundation

public enum WaitingHookRun {
  private struct Change {
    let location: HookConfigLocation
    let original: [UInt8]?
    let updated: [UInt8]
  }

  public static func status(locations: [HookConfigLocation], executablePath: String)
    -> ContextHookStatus
  {
    guard !locations.isEmpty else { return .notWired }
    var needsUpdate = false
    for location in locations {
      do {
        let original = try ConfigFileStore.read(location.file)
        guard let original,
          !WaitingHookSetup.entries(in: original, host: location.host).isEmpty
        else { return .notWired }
        let installed = try WaitingHookSetup.install(
          into: original, host: location.host, executablePath: executablePath)
        if installed != original { needsUpdate = true }
      } catch {
        return .unusable(SetupRun.describe(error))
      }
    }
    return needsUpdate ? .needsUpdate : .wired
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
    codexWaitingTrustFile: URL? = nil
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
        if location.host == .codex, let codexWaitingTrustFile {
          CodexHookTrust.recordWrittenWaiting(
            change.updated, at: location, in: codexWaitingTrustFile)
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
      updated = try WaitingHookSetup.install(
        into: original, host: location.host, executablePath: executablePath)
    } else {
      updated = try WaitingHookSetup.uninstall(from: original, host: location.host)
    }
    guard let updated, updated != original else { return nil }
    return Change(location: location, original: original, updated: updated)
  }

  private static func errorLine(_ error: any Error, in file: URL) -> String {
    "\(file.path): error: \(SetupRun.describe(error))"
  }
}
