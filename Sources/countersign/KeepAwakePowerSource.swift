import ApprovalCore
import Foundation
import IOKit.ps

enum KeepAwakePowerSource {
  static func current() -> KeepAwakePower {
    let description = internalBatteryDescription()
    return KeepAwakePower(
      internalBatteryState: description?[kIOPSPowerSourceStateKey] as? String,
      capacity: description?[kIOPSCurrentCapacityKey] as? Int,
      maxCapacity: description?[kIOPSMaxCapacityKey] as? Int)
  }

  private static func internalBatteryDescription() -> [String: Any]? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
      else { continue }
      return description
    }
    return nil
  }
}
