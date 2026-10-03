import Foundation
import SQLite3

public enum CursorStateDatabase {
  public static let applicationUserKey =
    "src.vs.platform.reactivestorage.browser.reactiveStorageServiceImpl.persistentStorage.applicationUser"

  private static let transientDestructor = unsafeBitCast(
    -1, to: sqlite3_destructor_type.self)

  public static func location(home: URL) -> URL {
    home
      .appendingPathComponent("Library")
      .appendingPathComponent("Application Support")
      .appendingPathComponent("Cursor")
      .appendingPathComponent("User")
      .appendingPathComponent("globalStorage")
      .appendingPathComponent("state.vscdb")
  }

  public static func value(forKey key: String, at url: URL) -> Data? {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(database)
      return nil
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 200)

    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database, "SELECT value FROM ItemTable WHERE key = ?1", -1, &statement, nil)
        == SQLITE_OK
    else {
      sqlite3_finalize(statement)
      return nil
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_bind_text(statement, 1, key, -1, transientDestructor) == SQLITE_OK,
      sqlite3_step(statement) == SQLITE_ROW,
      let bytes = sqlite3_column_blob(statement, 0)
    else { return nil }
    let count = Int(sqlite3_column_bytes(statement, 0))
    return Data(bytes: bytes, count: count)
  }
}
