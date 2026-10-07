import AppKit
import ApprovalCore

@MainActor
enum HookDiffDisclosure {
  static func view(diff: String, expanded: Bool = false, onResize: @escaping () -> Void) -> NSView {
    HookDiffDisclosureView(diff: diff, expanded: expanded, onResize: onResize)
  }

  static func accessoryView(
    for alert: NSAlert, text: String, isDiff: Bool, expanded: Bool = false
  ) -> NSView {
    guard isDiff else { return HookDiffPreview.view(text: text) }
    return view(diff: text, expanded: expanded) { [weak alert] in alert?.layout() }
  }

  static func collapsedLabel(for diff: String) -> String {
    "Show the change (\(DiffSummary(unifiedDiff: diff).text))"
  }

  static let expandedLabel = "Hide the change"
}

@MainActor
private final class HookDiffDisclosureView: NSStackView {
  private let triangle = NSButton()
  private let label = NSButton()
  private let preview: NSView
  private let collapsedLabel: String
  private let onResize: () -> Void

  init(diff: String, expanded: Bool, onResize: @escaping () -> Void) {
    preview = HookDiffPreview.view(text: diff)
    collapsedLabel = HookDiffDisclosure.collapsedLabel(for: diff)
    self.onResize = onResize
    super.init(frame: .zero)

    orientation = .vertical
    alignment = .leading
    spacing = 6

    triangle.setButtonType(.pushOnPushOff)
    triangle.bezelStyle = .disclosure
    triangle.title = ""
    triangle.target = self
    triangle.action = #selector(toggle)

    label.isBordered = false
    label.alignment = .left
    label.target = self
    label.action = #selector(toggle)
    label.setAccessibilityElement(false)

    let header = NSStackView(views: [triangle, label])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 4
    addArrangedSubview(header)
    preview.translatesAutoresizingMaskIntoConstraints = false
    widthAnchor.constraint(equalToConstant: preview.frame.width).isActive = true
    preview.widthAnchor.constraint(equalToConstant: preview.frame.width).isActive = true
    preview.heightAnchor.constraint(equalToConstant: preview.frame.height).isActive = true
    addArrangedSubview(preview)

    apply(expanded: expanded)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  private var isExpanded: Bool {
    !preview.isHidden
  }

  @objc private func toggle(_ sender: NSButton) {
    let expanded = sender === triangle ? triangle.state == .on : !isExpanded
    apply(expanded: expanded)
    onResize()
  }

  private func apply(expanded: Bool) {
    preview.isHidden = !expanded
    triangle.state = expanded ? .on : .off
    let text = expanded ? HookDiffDisclosure.expandedLabel : collapsedLabel
    label.title = text
    triangle.setAccessibilityLabel(text)
    triangle.setAccessibilityExpanded(expanded)
    layoutSubtreeIfNeeded()
    setFrameSize(fittingSize)
  }
}
