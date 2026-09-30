import AppKit
import ApprovalCore
import SwiftUI

@MainActor
@Observable
final class WaitingNoticeModel {
  let hostName: String
  let projectName: String
  let offersGoThere: Bool
  var onGoThere: (() -> Void)?
  var onDismiss: (() -> Void)?
  var onHeight: ((CGFloat) -> Void)?

  init(hostName: String, projectName: String, offersGoThere: Bool) {
    self.hostName = hostName
    self.projectName = projectName
    self.offersGoThere = offersGoThere
  }

  convenience init(record: WaitingRecord) {
    self.init(
      hostName: record.host.displayName, projectName: record.projectName,
      offersGoThere: record.appBundleID != nil)
  }

  var waitingText: String {
    "\(hostName) is waiting for you · "
  }

  var line: String {
    waitingText + projectName
  }
}

struct WaitingNoticeView: View {
  let model: WaitingNoticeModel

  @Environment(\.panelSurface) private var surface

  static let width: CGFloat = 340
  static let padding: CGFloat = 16

  var body: some View {
    VStack(alignment: .trailing, spacing: 12) {
      HStack(alignment: .center, spacing: 8) {
        HStack(spacing: 0) {
          Text(model.waitingText)
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
      if model.offersGoThere {
        Button("Go there") {
          model.onGoThere?()
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

final class WaitingNoticePanel: NSPanel {
  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: WaitingNoticeView.width, height: 80),
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
    fatalError("WaitingNoticePanel does not support NSCoding")
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class WaitingNoticeCard {
  static let screenInset: CGFloat = 16
  static let stackGap: CGFloat = 8
  private static let fallbackHeight: CGFloat = 94
  private static let fadeDuration: TimeInterval = 0.15

  private let panel = WaitingNoticePanel()
  private let model: WaitingNoticeModel
  private let hostingView: FirstClickHostingView<WaitingNoticeView>
  private let slot: Int
  private var screen: NSScreen?
  private var height: CGFloat = 0
  private var isClosed = false

  init(
    record: WaitingRecord, slot: Int, appearance: AppearanceChoice,
    onGoThere: @escaping @MainActor () -> Void, onDismiss: @escaping @MainActor () -> Void
  ) {
    let model = WaitingNoticeModel(record: record)
    self.model = model
    self.slot = slot
    hostingView = FirstClickHostingView(rootView: WaitingNoticeView(model: model))
    panel.appearance = appearance.windowAppearance
    panel.contentView = hostingView
    panel.setAccessibilityTitle("Countersign notice")
    model.onGoThere = onGoThere
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
    model.onGoThere = nil
    model.onDismiss = nil
    model.onHeight = nil
    panel.orderOut(nil)
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
    let width = WaitingNoticeView.width
    let top = visible.maxY - Self.screenInset - CGFloat(slot) * (height + Self.stackGap)
    let frame = NSRect(
      x: visible.maxX - Self.screenInset - width, y: top - height, width: width, height: height)
    panel.setFrame(frame, display: true)
  }
}
