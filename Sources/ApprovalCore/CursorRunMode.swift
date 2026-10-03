import Foundation

public enum CursorRunMode: String, Sendable, Equatable, CaseIterable {
  case asksEveryTime, allowlist, autoReview, runEverything, unknown

  public static func resolve(applicationUser: JSONValue) -> CursorRunMode {
    let composerState = applicationUser["composerState"]
    guard
      let agent = composerState?["modes4"]?.arrayValue?.first(where: {
        $0["id"]?.stringValue == "agent"
      }),
      let autoRun = agent["autoRun"]?.boolValue
    else { return .unknown }
    if !autoRun { return .asksEveryTime }
    guard
      let fullAutoRun = agent["fullAutoRun"]?.boolValue,
      let smartModeAutoRun = agent["smartModeAutoRun"]?.boolValue
    else { return .unknown }
    if fullAutoRun || composerState?["yoloEnableRunEverything"]?.boolValue == true {
      return .runEverything
    }
    if smartModeAutoRun { return .autoReview }
    return .allowlist
  }
}
