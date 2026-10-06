import AppKit

@MainActor
enum HookDiffPreview {
  static let lineCount: CGFloat = 12
  static let width: CGFloat = 520
  private static let inset: CGFloat = 6
  private static let borderThickness: CGFloat = 2

  static func view(text: String, width: CGFloat = HookDiffPreview.width) -> NSView {
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
    let maxHeight = lineHeight * lineCount + inset * 2 + borderThickness
    let scrollView = NSScrollView(
      frame: NSRect(origin: .zero, size: NSSize(width: width, height: maxHeight)))
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .bezelBorder
    scrollView.autohidesScrollers = true

    let contentWidth = scrollView.contentSize.width
    let textView = NSTextView(
      frame: NSRect(origin: .zero, size: NSSize(width: contentWidth, height: maxHeight)))
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: inset, height: inset)
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.lineBreakMode = .byCharWrapping
    textView.textStorage?.setAttributedString(attributed(text, font: font))
    scrollView.documentView = textView

    let contentHeight = measuredHeight(of: textView, width: contentWidth)
    let height = min(contentHeight + borderThickness, maxHeight)
    scrollView.setFrameSize(NSSize(width: width, height: height))
    textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: contentHeight))
    return scrollView
  }

  static func attributed(_ text: String, font: NSFont) -> NSAttributedString {
    let trimmed = text.hasSuffix("\n") ? String(text.dropLast()) : text
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byCharWrapping
    paragraphStyle.headIndent = markerColumnWidth(font: font)
    let result = NSMutableAttributedString()
    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
      if index > 0 {
        result.append(
          NSAttributedString(
            string: "\n", attributes: [.font: font, .paragraphStyle: paragraphStyle]))
      }
      result.append(
        NSAttributedString(
          string: String(line),
          attributes: [
            .font: font, .foregroundColor: color(for: line), .paragraphStyle: paragraphStyle,
          ]))
    }
    return result
  }

  private static func markerColumnWidth(font: NSFont) -> CGFloat {
    NSAttributedString(string: " ", attributes: [.font: font]).size().width
  }

  private static func measuredHeight(of textView: NSTextView, width: CGFloat) -> CGFloat {
    guard let layoutManager = textView.layoutManager, let container = textView.textContainer
    else { return 0 }
    container.containerSize = NSSize(
      width: width - inset * 2, height: CGFloat.greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: container)
    return ceil(layoutManager.usedRect(for: container).height) + inset * 2
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
