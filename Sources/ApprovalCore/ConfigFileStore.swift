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

  public static func backupName(
    for fileName: String, date: Date, timeZone: TimeZone = .current, sequence: Int = 1
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = sequence > 1 ? "-\(sequence)" : ""
    return "\(fileName).countersign-\(formatter.string(from: date))\(suffix).bak"
  }

  private static func freeBackupFile(
    for fileName: String, in directory: URL, date: Date, timeZone: TimeZone
  ) -> URL {
    var sequence = 1
    while true {
      let candidate = directory.appendingPathComponent(
        backupName(for: fileName, date: date, timeZone: timeZone, sequence: sequence))
      if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
      sequence += 1
    }
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
        let backupFile = freeBackupFile(
          for: target.lastPathComponent, in: directory, date: date, timeZone: timeZone)
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
    let backups = names.compactMap { name in
      backupOrder(of: name, fileName: fileName).map { (name: name, order: $0) }
    }
    .sorted { $0.order < $1.order }
    for backup in backups.dropLast(keptBackups) {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(backup.name))
    }
  }

  private static func backupOrder(of name: String, fileName: String) -> BackupOrder? {
    let prefix = "\(fileName).countersign-"
    let suffix = ".bak"
    guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
    let middle = String(name.dropFirst(prefix.count).dropLast(suffix.count))
    let parts = middle.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count >= 2, isDigits(parts[0], count: 8), isDigits(parts[1], count: 6) else {
      return nil
    }
    guard parts.count == 3 else { return BackupOrder(stamp: middle, sequence: 1) }
    guard let sequence = Int(parts[2]), sequence >= 2, parts[2].allSatisfy(\.isASCII) else {
      return nil
    }
    return BackupOrder(stamp: "\(parts[0])-\(parts[1])", sequence: sequence)
  }

  private static func isDigits(_ text: Substring, count: Int) -> Bool {
    text.count == count && text.allSatisfy { $0.isASCII && $0.isNumber }
  }

  private struct BackupOrder: Comparable {
    let stamp: String
    let sequence: Int

    static func < (lhs: BackupOrder, rhs: BackupOrder) -> Bool {
      (lhs.stamp, lhs.sequence) < (rhs.stamp, rhs.sequence)
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
