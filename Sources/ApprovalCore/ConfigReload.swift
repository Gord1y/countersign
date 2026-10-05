import Foundation

public struct ConfigReload {
  private let paths: AppPaths
  private let soundNames: [String]
  private var lastBytes: Data?

  public init(paths: AppPaths, soundNames: [String]) {
    self.paths = paths
    self.soundNames = soundNames
  }

  public mutating func changedFile() -> ConfigFile? {
    let bytes = (try? Data(contentsOf: paths.configFile)) ?? Data()
    guard let previous = lastBytes else {
      lastBytes = bytes
      return nil
    }
    guard bytes != previous else { return nil }
    lastBytes = bytes
    return ConfigFileLoader.load(paths: paths, soundNames: soundNames).file
  }
}
