import Darwin
import Foundation

public enum ConfigFileStore {
  static let keptBackups = 3

  public static func read(_ file: URL) throws -> [UInt8]? {
    do {
      return [UInt8](try Data(contentsOf: file))
    } catch CocoaError.fileReadNoSuchFile {
      return nil
    }
  }

  public static func fileState(_ file: URL) -> Doctor.FileState {
    do {
      guard let bytes = try read(file) else { return .missing }
      return .bytes(bytes)
    } catch {
      return .unreadable(SetupRun.describe(error))
    }
  }

  public static func backupName(for fileName: String, date: Date, timeZone: TimeZone = .current)
    -> String
  {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "\(fileName).countersign-\(formatter.string(from: date)).bak"
  }

  @discardableResult
  public static func write(
    _ bytes: [UInt8], to file: URL, date: Date, timeZone: TimeZone = .current,
    backingUp: Bool = true
  ) throws -> URL? {
    let target = file.resolvingSymlinksInPath()
    let directory = target.deletingLastPathComponent()
    var info = stat()
    var permissions: mode_t?
    var backup: URL?
    if stat(target.path, &info) == 0 {
      permissions = info.st_mode & 0o7777
      if backingUp {
        let backupFile = directory.appendingPathComponent(
          backupName(for: target.lastPathComponent, date: date, timeZone: timeZone))
        try FileManager.default.copyItem(at: target, to: backupFile)
        backup = backupFile
        pruneBackups(of: target.lastPathComponent, in: directory)
      }
    } else if errno != ENOENT {
      throw posixError()
    }
    let temporary = directory.appendingPathComponent(
      ".\(target.lastPathComponent).countersign-\(UUID().uuidString).tmp")
    try writeNewFile(bytes, at: temporary, permissions: permissions)
    guard rename(temporary.path, target.path) == 0 else {
      let error = posixError()
      unlink(temporary.path)
      throw error
    }
    return backup
  }

  private static func pruneBackups(of fileName: String, in directory: URL) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
      return
    }
    let backups = names.filter { isBackupName($0, of: fileName) }.sorted()
    for name in backups.dropLast(keptBackups) {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
  }

  private static func isBackupName(_ name: String, of fileName: String) -> Bool {
    let prefix = "\(fileName).countersign-"
    let suffix = ".bak"
    guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
    let stamp = Array(name.dropFirst(prefix.count).dropLast(suffix.count))
    return stamp.count == 15
      && stamp.indices.allSatisfy { index in
        index == 8 ? stamp[index] == "-" : stamp[index].isASCII && stamp[index].isNumber
      }
  }

  private static func writeNewFile(_ bytes: [UInt8], at file: URL, permissions: mode_t?) throws {
    let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o666)
    guard descriptor >= 0 else { throw posixError() }
    var failure = fill(descriptor, with: bytes, permissions: permissions)
    if close(descriptor) != 0, failure == nil {
      failure = posixError()
    }
    if let failure {
      unlink(file.path)
      throw failure
    }
  }

  private static func fill(_ descriptor: Int32, with bytes: [UInt8], permissions: mode_t?)
    -> POSIXError?
  {
    if let permissions, fchmod(descriptor, permissions) != 0 {
      return posixError()
    }
    var written = 0
    while written < bytes.count {
      let count = bytes[written...].withUnsafeBytes { buffer in
        Darwin.write(descriptor, buffer.baseAddress, buffer.count)
      }
      if count < 0, errno == EINTR {
        continue
      }
      guard count > 0 else { return posixError() }
      written += count
    }
    return fsync(descriptor) == 0 ? nil : posixError()
  }

  private static func posixError() -> POSIXError {
    POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
  }
}
