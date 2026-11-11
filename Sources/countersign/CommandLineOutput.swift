import ApprovalCore
import Foundation

enum CommandLineOutput {
  static func writeError(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }

  static func fail(_ message: String) -> Never {
    writeError(message)
    exit(1)
  }

  static func failOnUnusableConfig(paths: AppPaths) {
    do {
      if let problem = ConfigEdit.problem(in: try ConfigFileStore.read(paths.configFile)) {
        fail("error: config.json has a problem: \(problem)")
      }
    } catch {
      fail("error: config.json has a problem: \(SetupRun.describe(error))")
    }
  }
}
