import Foundation

public struct UpdateCheckAnswer: Sendable, Equatable {
  public let title: String
  public let message: String
  public let buttons: [UpdateCheckAnswerButton]

  public init(title: String, message: String, buttons: [UpdateCheckAnswerButton]) {
    self.title = title
    self.message = message
    self.buttons = buttons
  }

  public static func answer(
    for outcome: UpdateCheckOutcome, currentVersion: String, upgradeCommand: String,
    releaseNotesURL: URL?
  ) -> UpdateCheckAnswer {
    switch outcome {
    case .upToDate:
      return UpdateCheckAnswer(
        title: "Countersign is up to date",
        message: "You have \(currentVersion), the newest release.",
        buttons: [.ok])
    case .newerAvailable(let version):
      var buttons: [UpdateCheckAnswerButton] = [.copyUpgradeCommand(upgradeCommand)]
      if let releaseNotesURL {
        buttons.append(.openReleaseNotes(releaseNotesURL))
      }
      buttons.append(.later)
      return UpdateCheckAnswer(
        title: "Countersign \(version) is available",
        message: "You have \(currentVersion). To update, run:\n\(upgradeCommand)",
        buttons: buttons)
    case .unknown(let reason):
      return UpdateCheckAnswer(
        title: "Couldn't check for updates",
        message:
          "The list of releases couldn't be read (\(reason)). Check your connection and try again later.",
        buttons: [.ok])
    }
  }
}

public enum UpdateCheckAnswerButton: Sendable, Equatable {
  case ok
  case copyUpgradeCommand(String)
  case openReleaseNotes(URL)
  case later

  public var title: String {
    switch self {
    case .ok: return "OK"
    case .copyUpgradeCommand: return "Copy Upgrade Command"
    case .openReleaseNotes: return "Release Notes"
    case .later: return "Later"
    }
  }
}
