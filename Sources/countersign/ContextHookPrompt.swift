import AppKit
import ApprovalCore

@MainActor
enum ContextHookPrompt {
  static let cancelTitle = "Cancel"
  static let okTitle = "OK"
  static let previewLineCount: CGFloat = 12
  static let previewWidth: CGFloat = 520

  static func message(for change: ContextHookChange) -> String {
    guard change.origin == .toggle else { return "Update Countersign's Claude Code hook?" }
    return change.enable ? "Turn on context checkpoints?" : "Turn off context checkpoints?"
  }

  static func informativeText(for change: ContextHookChange, path: String) -> String {
    change.canApply ? "Countersign changes \(path) and keeps a backup." : ""
  }

  static func makeAlert(change: ContextHookChange, path: String) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = message(for: change)
    alert.informativeText = informativeText(for: change, path: path)
    alert.accessoryView = previewView(for: change)
    if change.canApply {
      alert.addButton(withTitle: change.confirmTitle)
      alert.addButton(withTitle: cancelTitle)
    } else {
      alert.addButton(withTitle: okTitle)
    }
    return alert
  }

  static func present(
    change: ContextHookChange, path: String, on window: NSWindow?,
    onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void
  ) {
    let alert = makeAlert(change: change, path: path)
    let canApply = change.canApply
    guard let window else {
      handle(alert.runModal(), canApply: canApply, onConfirm: onConfirm, onCancel: onCancel)
      return
    }
    alert.beginSheetModal(for: window) { response in
      handle(response, canApply: canApply, onConfirm: onConfirm, onCancel: onCancel)
    }
  }

  private static func handle(
    _ response: NSApplication.ModalResponse, canApply: Bool, onConfirm: () -> Void,
    onCancel: () -> Void
  ) {
    if canApply, response == .alertFirstButtonReturn {
      onConfirm()
    } else {
      onCancel()
    }
  }

  private static func previewView(for change: ContextHookChange) -> NSView {
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    let size = NSSize(width: previewWidth, height: lineHeight * previewLineCount + 12)
    let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.borderType = .bezelBorder
    scrollView.autohidesScrollers = true

    let textView = NSTextView(frame: NSRect(origin: .zero, size: size))
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 6, height: 6)
    textView.isHorizontallyResizable = true
    textView.isVerticallyResizable = true
    textView.autoresizingMask = []
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.containerSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textStorage?.setAttributedString(
      attributed(change.canApply ? change.preview.text : failureText(change), font: font))
    textView.sizeToFit()
    scrollView.documentView = textView
    return scrollView
  }

  private static func failureText(_ change: ContextHookChange) -> String {
    change.preview.failures.joined(separator: "\n")
  }

  static func attributed(_ text: String, font: NSFont) -> NSAttributedString {
    let trimmed = text.hasSuffix("\n") ? String(text.dropLast()) : text
    let result = NSMutableAttributedString()
    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
      if index > 0 {
        result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
      }
      result.append(
        NSAttributedString(
          string: String(line), attributes: [.font: font, .foregroundColor: color(for: line)]))
    }
    return result
  }

  private static func color(for line: Substring) -> NSColor {
    if line.hasPrefix("+"), !line.hasPrefix("+++") { return .systemGreen }
    if line.hasPrefix("-"), !line.hasPrefix("---") { return .systemRed }
    if line.hasPrefix("@@") || line.hasPrefix("---") || line.hasPrefix("+++") {
      return .secondaryLabelColor
    }
    return .labelColor
  }
}
