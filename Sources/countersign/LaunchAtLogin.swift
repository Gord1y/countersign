import ApprovalCore
import ServiceManagement

@MainActor
enum LaunchAtLogin {
  static var state: LaunchAtLoginState {
    switch SMAppService.mainApp.status {
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    case .notRegistered, .notFound: return .notRegistered
    @unknown default: return .unavailable
    }
  }

  static func register() throws {
    try SMAppService.mainApp.register()
  }

  static func unregister() throws {
    try SMAppService.mainApp.unregister()
  }

  static func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
