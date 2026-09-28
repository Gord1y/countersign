import Foundation

public enum ConfigFileStarter {
  public static let contents = """
    {
      "$schema": "https://raw.githubusercontent.com/Gord1y/countersign/main/schema/config.schema.json"
    }

    """

  public static func createIfMissing(paths: AppPaths) throws -> Bool {
    let file = paths.configFile
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
      try Data(contents.utf8).write(to: file, options: .withoutOverwriting)
    } catch CocoaError.fileWriteFileExists {
      return false
    }
    return true
  }
}
