import AppKit
import ApprovalCore
import SwiftUI

@MainActor
@Observable
final class TestPanelResultCardModel {
  let title: String
  let detail: String
  var onHeight: ((CGFloat) -> Void)?
  var onDismiss: (() -> Void)?
  var onHover: ((Bool) -> Void)?

  init(title: String, detail: String) {
    self.title = title
    self.detail = detail
  }
}

struct TestPanelResultCardView: View {
  let model: TestPanelResultCardModel
  let width: CGFloat

  @State private var detailHeight: CGFloat = 0
  @Environment(\.panelSurface) private var surface

  static let visibleLines: CGFloat = 8
  static let closeButtonReserve: CGFloat = 24
  static let detailFont = NSFont.systemFont(ofSize: 13)

  private static var maximumDetailHeight: CGFloat {
    let lineHeight = ceil(detailFont.ascender - detailFont.descender + detailFont.leading)
    return lineHeight * visibleLines
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(model.title)
        .font(PanelTypography.title)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.trailing, Self.closeButtonReserve)
      ScrollView(.vertical) {
        Text(model.detail)
          .font(PanelTypography.body)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
          .reportHeight { detailHeight = $0 }
      }
      .frame(height: min(detailHeight, Self.maximumDetailHeight))
    }
    .padding(PanelMetrics.padding)
    .frame(width: width, alignment: .leading)
    .background(surface.fill)
    .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
    )
    .overlay(alignment: .topTrailing) {
      Button {
        model.onDismiss?()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 24, height: 24)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Dismiss")
      .help("Dismiss")
      .padding(6)
    }
    .reportHeight { model.onHeight?($0) }
    .contentShape(Rectangle())
    .onTapGesture { model.onDismiss?() }
    .onHover { model.onHover?($0) }
  }
}

@MainActor
final class TestPanelResultCard {
  static let width: CGFloat = 420
  static let dismissDelay: Duration = .seconds(4)
  private static let escapeKeyCode: UInt16 = 53
  private static let initialHeight: CGFloat = 100

  private let panel: ApprovalPanel
  private let hostingController: NSHostingController<TestPanelResultCardView>
  private var center: NSPoint
  private let onClose: @MainActor () -> Void
  private var dismissTask: Task<Void, Never>?
  private var keyMonitor: Any?
  private var isClosed = false

  init(
    title: String, detail: String, around frame: NSRect, appearance: AppearanceChoice,
    onClose: @escaping @MainActor () -> Void
  ) {
    let model = TestPanelResultCardModel(title: title, detail: detail)
    let panel = ApprovalPanel()
    let hostingController = NSHostingController(
      rootView: TestPanelResultCardView(model: model, width: Self.width))
    self.panel = panel
    self.hostingController = hostingController
    self.center = NSPoint(x: frame.midX, y: frame.midY)
    self.onClose = onClose

    panel.appearance = appearance.windowAppearance
    panel.contentViewController = hostingController
    panel.onEscape = { [weak self] in self?.dismiss() }
    model.onDismiss = { [weak self] in self?.dismiss() }
    model.onHover = { [weak self] hovering in
      if hovering {
        self?.dismissTask?.cancel()
      } else {
        self?.startCountdown()
      }
    }
    model.onHeight = { [weak self] height in self?.applyHeight(height) }
    applyHeight(Self.initialHeight)
  }

  func show() {
    hostingController.view.layoutSubtreeIfNeeded()
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.makeFirstResponder(nil)
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.panel.isKeyWindow, event.keyCode == Self.escapeKeyCode else {
        return event
      }
      self.dismiss()
      return nil
    }
    startCountdown()
  }

  private func startCountdown() {
    guard !isClosed else { return }
    dismissTask?.cancel()
    dismissTask = Task { [weak self] in
      try? await Task.sleep(for: Self.dismissDelay)
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    dismissTask?.cancel()
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
    }
    keyMonitor = nil
    panel.orderOut(nil)
  }

  private func dismiss() {
    guard !isClosed else { return }
    close()
    onClose()
  }

  func followScreenChange() {
    guard let placed = NSScreen.placement(for: panel.frame) else { return }
    center = NSPoint(x: placed.frame.midX, y: placed.frame.midY)
    applyHeight(placed.frame.height)
  }

  private func applyHeight(_ height: CGFloat) {
    let centred = NSRect(
      x: center.x - Self.width / 2, y: center.y - height / 2, width: Self.width, height: height)
    panel.setFrame(NSScreen.placement(for: centred)?.frame ?? centred, display: true)
  }
}
