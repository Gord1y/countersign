import AppKit

@MainActor
enum HookDiffPreview {
  static let lineCount: CGFloat = 12
  static let width: CGFloat = 520

  static func view(text: String) -> NSView {
    let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    let size = NSSize(width: width, height: lineHeight * lineCount + 12)
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
    textView.textStorage?.setAttributedString(attributed(text, font: font))
    textView.sizeToFit()
    scrollView.documentView = textView
    return scrollView
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
