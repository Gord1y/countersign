import Foundation

public enum KeepAwakeConfigRead: Sendable, Equatable {
  case usable(optedIn: Bool, cutoff: Int)
  case problem

  public static func current(paths: AppPaths) -> KeepAwakeConfigRead {
    let bytes: [UInt8]?
    do {
      bytes = try ConfigFileStore.read(paths.configFile)
    } catch {
      return .problem
    }
    guard ConfigEdit.problem(in: bytes) == nil else { return .problem }
    let file = bytes.map { ConfigFileParser.parse(Data($0)).file } ?? ConfigFile()
    return .usable(
      optedIn: file.keepAwake ?? Settings.defaultKeepAwake,
      cutoff: file.keepAwakeBatteryCutoff ?? Settings.defaultKeepAwakeBatteryCutoff)
  }
}
