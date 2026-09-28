import Foundation

public enum UpdateCommand {
  public static let brewUpgradeCommand = "brew upgrade countersign"
  public static let curlInstallCommand =
    "curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | sh"

  public static func upgrade(forResolvedExecutablePath path: String) -> String {
    path.contains(StableExecutablePath.cellarMarker) ? brewUpgradeCommand : curlInstallCommand
  }

  public static func releaseNotesURL(version: String) -> URL? {
    URL(string: "https://github.com/Gord1y/countersign/releases/tag/v\(version)")
  }
}
