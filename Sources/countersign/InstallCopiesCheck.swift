import ApprovalCore
import Foundation
import os

enum InstallCopiesCheck {
  struct ProbedFile: Hashable, Sendable {
    let path: String
    let modified: Date
    let size: Int

    init?(path: String) {
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
        let modified = attributes[.modificationDate] as? Date,
        let size = (attributes[.size] as? NSNumber)?.intValue
      else { return nil }
      self.path = path
      self.modified = modified
      self.size = size
    }
  }

  static let versionTimeout: DispatchTimeInterval = .seconds(2)
  static let systemRoot = URL(fileURLWithPath: "/", isDirectory: true)
  static let probedVersions = OSAllocatedUnfairLock<[ProbedFile: String?]>(initialState: [:])

  static func duplicates(
    hookExecutables: [String], runningExecutable: String?, home: URL, root: URL = systemRoot,
    probesVersions: Bool = true
  ) -> DuplicateInstall? {
    InstalledCopies.duplicates(
      home: home, root: root, fileSystem: .local,
      cliVersion: probesVersions ? probedCLIVersion : { _ in nil },
      hookExecutables: hookExecutables, runningExecutable: runningExecutable)
  }

  static func versionMismatch(home: URL, root: URL = systemRoot, probesVersions: Bool = true)
    -> InstallVersionMismatch?
  {
    InstalledCopies.versionMismatch(
      home: home, root: root, fileSystem: .local,
      cliVersion: probesVersions ? probedCLIVersion : { _ in nil })
  }

  static func probedCLIVersion(_ path: String) -> String? {
    guard let file = ProbedFile(path: path) else { return cliVersion(path) }
    if let known = probedVersions.withLock({ $0[file] }) {
      return known
    }
    let version = cliVersion(path)
    probedVersions.withLock { $0[file] = version }
    return version
  }

  static func hookExecutables(in locations: [HookConfigLocation]) -> [String] {
    locations.flatMap { location -> [String] in
      guard let bytes = try? ConfigFileStore.read(location.file) else { return [] }
      return Doctor.executablePaths(inHookConfig: bytes, host: location.host)
    }
  }

  static func cliVersion(_ path: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["--version"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do {
      try process.run()
    } catch {
      return nil
    }
    guard finished.wait(timeout: .now() + versionTimeout) == .success else {
      process.terminate()
      return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return InstalledCopies.version(fromVersionOutput: String(decoding: data, as: UTF8.self))
  }
}
