import AppKit
import ApprovalCore

struct HostApp {
  let localizedName: String
  let bundleIdentifier: String
  let processIdentifier: pid_t

  static func resolve(ancestry: [Int32] = ProcessAncestry.chain(from: getppid())) -> HostApp? {
    for pid in ancestry {
      guard let app = NSRunningApplication(processIdentifier: pid_t(pid)),
        app.activationPolicy == .regular,
        let bundleIdentifier = app.bundleIdentifier
      else {
        continue
      }
      return HostApp(
        localizedName: app.localizedName ?? bundleIdentifier,
        bundleIdentifier: bundleIdentifier,
        processIdentifier: app.processIdentifier)
    }
    return nil
  }
}
