import AppKit
import ApprovalCore
import CoreGraphics
import Foundation

@MainActor
final class SystemActivity: NSObject {
  private static let inputEventTypes: [CGEventType] = [
    .keyDown, .keyUp, .flagsChanged,
    .leftMouseDown, .rightMouseDown, .otherMouseDown,
    .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    .scrollWheel,
  ]
  private static let heldModifierFlags: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn,
  ]
  private static let inputSourceChangedNotification = Notification.Name(
    "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")

  private var inputSourceChangeUptime: TimeInterval?
  private var spaceChangeUptime: TimeInterval?
  private var missionControlSeenUptime: TimeInterval?
  private(set) var isMissionControlShowing = false

  override init() {
    super.init()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(inputSourceChanged(_:)),
      name: Self.inputSourceChangedNotification, object: nil,
      suspensionBehavior: .deliverImmediately)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(activeSpaceChanged(_:)),
      name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
  }

  func secondsSinceLastInput() -> Double {
    let now = ProcessInfo.processInfo.systemUptime
    isMissionControlShowing = MissionControl.isShowing(
      windows: Self.onScreenDockWindows(), displays: Self.activeDisplayBounds())
    if isMissionControlShowing {
      missionControlSeenUptime = now
    }
    let sinceLastEvent =
      Self.inputEventTypes.map {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
      }.min() ?? .infinity
    let sinceInputSourceChange = inputSourceChangeUptime.map { now - $0 } ?? .infinity
    let sinceSpaceChange = spaceChangeUptime.map { now - $0 } ?? .infinity
    let sinceMissionControl = missionControlSeenUptime.map { now - $0 } ?? .infinity
    return min(sinceLastEvent, sinceInputSourceChange, sinceSpaceChange, sinceMissionControl)
  }

  func modifiersHeld() -> Bool {
    !CGEventSource.flagsState(.combinedSessionState).intersection(Self.heldModifierFlags).isEmpty
  }

  private static func onScreenDockWindows() -> [MissionControl.Window] {
    guard
      let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [NSDictionary]
    else { return [] }
    return windows.compactMap { info in
      guard let ownerName = info[kCGWindowOwnerName as String] as? String,
        ownerName == MissionControl.overlayOwnerName,
        let layer = info[kCGWindowLayer as String] as? Int,
        let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
      else { return nil }
      return MissionControl.Window(ownerName: ownerName, layer: layer, bounds: bounds)
    }
  }

  private static func activeDisplayBounds() -> [CGRect] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
    return displays.prefix(Int(count)).map(CGDisplayBounds)
  }

  @objc nonisolated private func inputSourceChanged(_ notification: Notification) {
    let uptime = ProcessInfo.processInfo.systemUptime
    Task { @MainActor [weak self] in
      self?.inputSourceChangeUptime = uptime
    }
  }

  @objc nonisolated private func activeSpaceChanged(_ notification: Notification) {
    let uptime = ProcessInfo.processInfo.systemUptime
    Task { @MainActor [weak self] in
      self?.spaceChangeUptime = uptime
    }
  }
}
