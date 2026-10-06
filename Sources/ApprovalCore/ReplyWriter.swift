import Foundation

public enum ReplyWriter {
  @discardableResult
  public static func write(_ data: Data, to handle: FileHandle) -> Bool {
    var line = data
    line.append(0x0A)
    do {
      try handle.write(contentsOf: line)
      return true
    } catch {
      return false
    }
  }
}
