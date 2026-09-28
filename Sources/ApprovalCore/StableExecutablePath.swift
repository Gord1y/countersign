import Foundation

public enum StableExecutablePath {
  static let cellarMarker = "/Cellar/countersign/"
  static let appBundleSuffix = "/Countersign.app/Contents/MacOS/" + HookCommand.executableName

  public static func cliPath(home: URL) -> String {
    home.appendingPathComponent(".local").appendingPathComponent("bin")
      .appendingPathComponent(HookCommand.executableName).path
  }

  public static func stable(
    forResolved path: String, home: URL, isExecutable: (String) -> Bool
  ) -> String {
    if let marker = path.range(of: cellarMarker) {
      return String(path[..<marker.lowerBound]) + "/bin/" + HookCommand.executableName
    }
    guard path.hasSuffix(appBundleSuffix) else { return path }
    let cli = cliPath(home: home)
    return isExecutable(cli) ? cli : path
  }
}
