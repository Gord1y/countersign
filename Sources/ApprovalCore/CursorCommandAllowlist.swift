import Foundation

public struct CursorCommandAllowlist: Sendable, Equatable {
  public enum Source: String, Sendable, Equatable { case inApp, permissionsFiles }

  public let patterns: [String]
  public let source: Source

  public init(patterns: [String], source: Source) {
    self.patterns = patterns
    self.source = source
  }

  public static func resolve(inApp: [String]?, permissionsFiles: [[String]?])
    -> CursorCommandAllowlist?
  {
    let definedFiles = permissionsFiles.compactMap { $0 }
    if permissionsFiles.contains(where: { $0 != nil }) {
      return CursorCommandAllowlist(
        patterns: definedFiles.flatMap { $0 }, source: .permissionsFiles)
    }
    guard let inApp else { return nil }
    return CursorCommandAllowlist(patterns: inApp, source: .inApp)
  }
}
