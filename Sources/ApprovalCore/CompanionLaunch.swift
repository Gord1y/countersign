import CoreServices

public enum CompanionLaunch {
  public static let openSettingsNotificationName = "\(AppLaunchMode.bundleIdentifier).openSettings"

  public static func opensSettings(launchEventID: AEEventID?, launchedAs: OSType?) -> Bool {
    let isOpenApplication = launchEventID == AEEventID(kAEOpenApplication)
    let isLoginItem = launchedAs == OSType(keyAELaunchedAsLogInItem)
    return !(isOpenApplication && isLoginItem)
  }
}
