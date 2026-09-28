import Foundation

enum CommandLineOutput {
  static func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }

  static func fail(_ message: String) -> Never {
    writeError(message)
    exit(1)
  }
}
