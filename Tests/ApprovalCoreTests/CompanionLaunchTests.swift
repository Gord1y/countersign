import CoreServices
import Testing

@testable import ApprovalCore

@Suite struct CompanionLaunchTests {
  private static let openApplication = AEEventID(kAEOpenApplication)
  private static let loginItem = OSType(keyAELaunchedAsLogInItem)

  @Test func namesTheNotificationUnderTheBundleIdentifier() {
    #expect(CompanionLaunch.openSettingsNotificationName == "dev.gord1y.countersign.openSettings")
  }

  @Test func namesTheOpenSetupNotificationAndArgument() {
    #expect(CompanionLaunch.openSetupNotificationName == "dev.gord1y.countersign.openSetup")
    #expect(CompanionLaunch.setupArgument == "--setup")
  }

  @Test func staysInTheMenuBarWhenLaunchedAsALoginItem() {
    #expect(
      !CompanionLaunch.opensSettings(
        launchEventID: Self.openApplication, launchedAs: Self.loginItem))
  }

  @Test func opensSettingsWhenThePersonOpensTheApp() {
    #expect(CompanionLaunch.opensSettings(launchEventID: Self.openApplication, launchedAs: nil))
  }

  @Test func opensSettingsWithoutALaunchEvent() {
    #expect(CompanionLaunch.opensSettings(launchEventID: nil, launchedAs: nil))
  }

  @Test func opensSettingsForAServiceItemLaunch() {
    #expect(
      CompanionLaunch.opensSettings(
        launchEventID: Self.openApplication, launchedAs: OSType(keyAELaunchedAsServiceItem)))
  }

  @Test func needsTheOpenApplicationEventForALoginLaunch() {
    #expect(
      CompanionLaunch.opensSettings(
        launchEventID: AEEventID(kAEReopenApplication), launchedAs: Self.loginItem))
  }

  @Test func readsTheCodesFromTheSDK() {
    #expect(Self.openApplication == 0x6F61_7070)
    #expect(Self.loginItem == 0x6C67_6974)
  }
}
