import AppKit
import ApprovalCore
import SwiftUI

@MainActor
@Observable
final class CornerCardModel {
  let leadText: String
  let projectName: String
  let actionTitle: String?
  var onAction: (() -> Void)?
  var onDismiss: (() -> Void)?
  var onHeight: ((CGFloat) -> Void)?

  init(leadText: String, projectName: String, actionTitle: String?) {
    self.leadText = leadText
    self.projectName = projectName
    self.actionTitle = actionTitle
  }

  static func waitingNotice(hostName: String, projectName: String, offersGoThere: Bool)
    -> CornerCardModel
  {
    CornerCardModel(
      leadText: "\(hostName) is waiting for you · ", projectName: projectName,
      actionTitle: offersGoThere ? "Go there" : nil)
  }

  static func waitingNotice(record: WaitingRecord) -> CornerCardModel {
    waitingNotice(
      hostName: record.host.displayName, projectName: record.projectName,
      offersGoThere: record.appBundleID != nil)
  }

  static func approval(hostName: String, projectName: String) -> CornerCardModel {
    CornerCardModel(
      leadText: "\(hostName) needs your approval · ", projectName: projectName,
      actionTitle: "Show")
  }

  var line: String {
    leadText + projectName
  }
}

struct CornerCardView: View {
  let model: CornerCardModel

  @Environment(\.panelSurface) private var surface

  static let width: CGFloat = 340
  static let padding: CGFloat = 16

  var body: some View {
    VStack(alignment: .trailing, spacing: 12) {
      HStack(alignment: .center, spacing: 8) {
        HStack(spacing: 0) {
          Text(model.leadText)
            .fixedSize()
          Text(model.projectName)
            .truncationMode(.middle)
        }
        .lineLimit(1)
        .font(PanelTypography.body.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.line)
        Button {
          model.onDismiss?()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
      }
      if let actionTitle = model.actionTitle {
        Button(actionTitle) {
          model.onAction?()
        }
        .buttonStyle(PrimaryButtonStyle())
      }
    }
    .padding(Self.padding)
    .frame(width: Self.width)
    .background(surface.fill)
    .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
    .overlay(
      PanelBorder(
        shape: RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous),
        opacity: 0.1)
    )
    .reportHeight { model.onHeight?($0) }
  }
}

final class CornerCardPanel: NSPanel {
  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: CornerCardView.width, height: 80),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isFloatingPanel = true
    level = ApprovalPanel.floatingLevel
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    hidesOnDeactivate = false
    isMovable = false
    animationBehavior = .none
  }

  required init?(coder: NSCoder) {
    fatalError("CornerCardPanel does not support NSCoding")
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CornerCard {
  static let screenInset: CGFloat = 16
  static let stackGap: CGFloat = 8
  private static let fallbackHeight: CGFloat = 94
  private static let fadeDuration: TimeInterval = 0.15

  private let panel = CornerCardPanel()
  private let model: CornerCardModel
  private let hostingView: FirstClickHostingView<CornerCardView>
  let slot: Int
  private let slotLock: ExclusiveFileLock
  private var screen: NSScreen?
  private var height: CGFloat = 0
  private var isClosed = false

  static func inFreeSlot(
    of store: WaitingStore, model: CornerCardModel, accessibilityTitle: String,
    appearance: AppearanceChoice, onAction: @escaping @MainActor () -> Void,
    onDismiss: @escaping @MainActor () -> Void
  ) -> CornerCard? {
    for slot in 0..<WaitingStore.slotCount {
      if let slotLock = try? ExclusiveFileLock.acquire(store.slotLockFile(slot)) {
        return CornerCard(
          model: model, slot: slot, slotLock: slotLock, accessibilityTitle: accessibilityTitle,
          appearance: appearance, onAction: onAction, onDismiss: onDismiss)
      }
    }
    return nil
  }

  private init(
    model: CornerCardModel, slot: Int, slotLock: ExclusiveFileLock, accessibilityTitle: String,
    appearance: AppearanceChoice, onAction: @escaping @MainActor () -> Void,
    onDismiss: @escaping @MainActor () -> Void
  ) {
    self.model = model
    self.slot = slot
    self.slotLock = slotLock
    hostingView = FirstClickHostingView(rootView: CornerCardView(model: model))
    panel.appearance = appearance.windowAppearance
    panel.contentView = hostingView
    panel.setAccessibilityTitle(accessibilityTitle)
    model.onAction = onAction
    model.onDismiss = onDismiss
    model.onHeight = { [weak self] height in self?.applyHeight(height) }
  }

  func show() {
    screen = PanelController.resolveTargetScreen()
    hostingView.layoutSubtreeIfNeeded()
    hostingView.layoutSubtreeIfNeeded()
    let measured = hostingView.fittingSize.height
    applyHeight(measured > 0 ? measured : Self.fallbackHeight)
    let fadesIn = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    panel.alphaValue = fadesIn ? 0 : 1
    panel.orderFrontRegardless()
    NSAccessibility.post(
      element: panel, notification: .announcementRequested,
      userInfo: [
        .announcement: model.line,
        .priority: NSAccessibilityPriorityLevel.high.rawValue,
      ])
    guard fadesIn else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.fadeDuration
      panel.animator().alphaValue = 1
    }
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    model.onAction = nil
    model.onDismiss = nil
    model.onHeight = nil
    panel.orderOut(nil)
    slotLock.release()
  }

  func followScreenChange() {
    guard !isClosed, let placed = NSScreen.placement(for: panel.frame) else { return }
    screen = placed.screen
    place()
  }

  private func applyHeight(_ measured: CGFloat) {
    let rounded = ceil(measured)
    guard rounded > 0, rounded != height else { return }
    height = rounded
    place()
  }

  private func place() {
    guard height > 0, let visible = (screen ?? PanelController.resolveTargetScreen())?.visibleFrame
    else { return }
    let width = CornerCardView.width
    let top = visible.maxY - Self.screenInset - CGFloat(slot) * (height + Self.stackGap)
    let frame = NSRect(
      x: visible.maxX - Self.screenInset - width, y: top - height, width: width, height: height)
    panel.setFrame(frame, display: true)
  }
}
