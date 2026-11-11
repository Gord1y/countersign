public enum CompanionProbe {
  public static func isRunning(paths: AppPaths) -> Bool {
    do {
      guard let lock = try ExclusiveFileLock.acquire(paths.companionLockFile) else {
        return true
      }
      lock.release()
      return false
    } catch {
      return false
    }
  }
}
