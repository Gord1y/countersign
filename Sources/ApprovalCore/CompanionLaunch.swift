import CoreServices

public enum CompanionLaunch {
  public static let openSettingsNotificationName = "\(AppLaunchMode.bundleIdentifier).openSettings"
  public static let openSetupNotificationName = "\(AppLaunchMode.bundleIdentifier).openSetup"
  public static let setupArgument = "--setup"

  public static func opensSettings(launchEventID: AEEventID?, launchedAs: OSType?) -> Bool {
    let isOpenApplication = launchEventID == AEEventID(kAEOpenApplication)
    let isLoginItem = launchedAs == OSType(keyAELaunchedAsLogInItem)
    return !(isOpenApplication && isLoginItem)
  }
}
