import Foundation
import Testing

@testable import ApprovalCore

@Suite struct KeepAwakeConfigTests {
  private func paths() -> AppPaths {
    AppPaths(
      home: FileManager.default.temporaryDirectory
        .appendingPathComponent("countersign-keepawake-config-\(UUID().uuidString)"))
  }

  private func remove(_ paths: AppPaths) {
    try? FileManager.default.removeItem(at: paths.home)
  }

  private func writeConfig(_ text: String, to paths: AppPaths) throws {
    try FileManager.default.createDirectory(
      at: paths.configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: paths.configFile)
  }

  @Test func anAbsentFileIsUsableAndOptedOut() {
    let paths = paths()
    defer { remove(paths) }

    #expect(
      KeepAwakeConfigRead.current(paths: paths)
        == .usable(optedIn: false, cutoff: Settings.defaultKeepAwakeBatteryCutoff))
  }

  @Test func anEmptyObjectIsUsableAndOptedOut() throws {
    let paths = paths()
    defer { remove(paths) }
    try writeConfig("{}", to: paths)

    #expect(
      KeepAwakeConfigRead.current(paths: paths)
        == .usable(optedIn: false, cutoff: Settings.defaultKeepAwakeBatteryCutoff))
  }

  @Test func keepAwakeAndItsCutoffAreRead() throws {
    let paths = paths()
    defer { remove(paths) }
    try writeConfig(#"{"keepAwake": true, "keepAwakeBatteryCutoff": 25}"#, to: paths)

    #expect(KeepAwakeConfigRead.current(paths: paths) == .usable(optedIn: true, cutoff: 25))
  }

  @Test func invalidJSONIsAProblem() throws {
    let paths = paths()
    defer { remove(paths) }
    try writeConfig(#"{"keepAwake": tru"#, to: paths)

    #expect(KeepAwakeConfigRead.current(paths: paths) == .problem)
  }

  @Test func aJSONArrayAtTheRootIsAProblem() throws {
    let paths = paths()
    defer { remove(paths) }
    try writeConfig("[true]", to: paths)

    #expect(KeepAwakeConfigRead.current(paths: paths) == .problem)
  }

  @Test func anUnreadablePathIsAProblem() throws {
    let paths = paths()
    defer { remove(paths) }
    try FileManager.default.createDirectory(
      at: paths.configFile, withIntermediateDirectories: true)

    #expect(KeepAwakeConfigRead.current(paths: paths) == .problem)
  }
}
