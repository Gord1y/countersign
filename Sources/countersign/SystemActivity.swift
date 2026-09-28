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

  override init() {
    super.init()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(inputSourceChanged(_:)),
      name: Self.inputSourceChangedNotification, object: nil,
      suspensionBehavior: .deliverImmediately)
  }

  func secondsSinceLastInput() -> Double {
    let sinceLastEvent =
      Self.inputEventTypes.map {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
      }.min() ?? .infinity
    let sinceInputSourceChange =
      inputSourceChangeUptime.map { ProcessInfo.processInfo.systemUptime - $0 } ?? .infinity
    return min(sinceLastEvent, sinceInputSourceChange)
  }

  func modifiersHeld() -> Bool {
    !CGEventSource.flagsState(.combinedSessionState).intersection(Self.heldModifierFlags).isEmpty
  }

  @objc nonisolated private func inputSourceChanged(_ notification: Notification) {
    let uptime = ProcessInfo.processInfo.systemUptime
    Task { @MainActor [weak self] in
      self?.inputSourceChangeUptime = uptime
    }
  }
}
