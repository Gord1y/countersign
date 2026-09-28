public enum HandoffCheck {
  public static func shouldHandOff(
    frontmostBundleID: String?,
    frontmostPID: Int32?,
    handoffApps: [String],
    hostAppPID: Int32?
  ) -> Bool {
    guard let frontmostBundleID, handoffApps.contains(frontmostBundleID) else {
      return false
    }
    guard let hostAppPID else {
      return true
    }
    return frontmostPID == hostAppPID
  }
}
