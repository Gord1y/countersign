import Testing

@testable import ApprovalCore

@Suite struct AppLaunchModeTests {
  @Test func appModeWithTheAppBundleIDAndNoArguments() {
    #expect(
      AppLaunchMode.detect(bundleIdentifier: "dev.gord1y.countersign", arguments: []) == .app)
  }

  @Test func appModeIgnoresAnOlderLaunchServicesProcessSerialNumberArgument() {
    #expect(
      AppLaunchMode.detect(bundleIdentifier: "dev.gord1y.countersign", arguments: ["-psn_0_12345"])
        == .app)
  }

  @Test func cliModeWithAnUnrelatedBundleID() {
    #expect(AppLaunchMode.detect(bundleIdentifier: "com.example.other", arguments: []) == .cli)
  }

  @Test func cliModeWithNoBundleID() {
    #expect(AppLaunchMode.detect(bundleIdentifier: nil, arguments: []) == .cli)
  }

  @Test func cliModeWithRealArguments() {
    #expect(
      AppLaunchMode.detect(bundleIdentifier: "dev.gord1y.countersign", arguments: ["hook"])
        == .cli)
  }

  @Test func cliModeWithRealArgumentsAlongsideAProcessSerialNumber() {
    #expect(
      AppLaunchMode.detect(
        bundleIdentifier: "dev.gord1y.countersign", arguments: ["-psn_0_12345", "hook"])
        == .cli)
  }
}
