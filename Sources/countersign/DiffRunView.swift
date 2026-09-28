import AppKit
import ApprovalCore
import SwiftUI

enum DiffGutter: Sendable, Equatable {
  case numbered
  case markerOnly

  static let horizontalPadding: CGFloat = 8
  static let numberColumnWidth: CGFloat = 34
  static let markerColumnWidth: CGFloat = 14

  var markerColumnX: CGFloat {
    switch self {
    case .numbered: return Self.horizontalPadding + Self.numberColumnWidth * 2
    case .markerOnly: return Self.horizontalPadding
    }
  }

  var textColumnX: CGFloat { markerColumnX + Self.markerColumnWidth }

  func textWidth(forRowWidth width: CGFloat) -> CGFloat {
    width - textColumnX - Self.horizontalPadding
  }
}

struct DiffRunView: NSViewRepresentable {
  let lines: [NumberedLine]
  let gutter: DiffGutter

  func makeNSView(context: Context) -> DiffRunHostView {
    DiffRunHostView(lines: lines, gutter: gutter)
  }

  func updateNSView(_ nsView: DiffRunHostView, context: Context) {
    nsView.update(lines: lines, gutter: gutter)
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: DiffRunHostView, context: Context)
    -> CGSize?
  {
    guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
    return CGSize(width: width, height: nsView.height(forWidth: width))
  }
}

private struct DiffRunPalette {
  let text: NSColor
  let gutter: NSColor
  let addedBackground: NSColor
  let removedBackground: NSColor

  init(appearance: NSAppearance) {
    if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
      text = NSColor(srgbRed: 0.90, green: 0.90, blue: 0.90, alpha: 1)
      gutter = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.45, alpha: 1)
      addedBackground = NSColor(srgbRed: 0.188, green: 0.820, blue: 0.345, alpha: 0.13)
      removedBackground = NSColor(srgbRed: 1, green: 0.271, blue: 0.227, alpha: 0.13)
    } else {
      text = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)
      gutter = NSColor(srgbRed: 0.66, green: 0.66, blue: 0.66, alpha: 1)
      addedBackground = NSColor(srgbRed: 0.204, green: 0.780, blue: 0.349, alpha: 0.13)
      removedBackground = NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 0.13)
    }
  }

  func background(for kind: NumberedLineKind) -> NSColor? {
    switch kind {
    case .added: return addedBackground
    case .removed: return removedBackground
    case .context: return nil
    }
  }
}

private struct DiffRowSpan {
  let top: CGFloat
  let bottom: CGFloat
}

private final class DiffRunTextView: NSTextView {
  override var allowsVibrancy: Bool { false }
}

final class DiffRunHostView: NSView {
  private static let rowPadding: CGFloat = 1
  private static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
  private static let numberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

  private let textView: DiffRunTextView
  private var lines: [NumberedLine]
  private var gutter: DiffGutter
  private var measuredWidth: CGFloat?
  private var rowSpans: [DiffRowSpan] = []
  private var rowEndOffsets: [Int] = []

  init(lines: [NumberedLine], gutter: DiffGutter) {
    self.textView = DiffRunTextView(usingTextLayoutManager: true)
    self.lines = lines
    self.gutter = gutter
    super.init(frame: .zero)
    configureTextView()
    addSubview(textView)
    applyText()
  }

  required init?(coder: NSCoder) {
    fatalError("DiffRunHostView does not support NSCoding")
  }

  override var isFlipped: Bool { true }
  override var allowsVibrancy: Bool { false }

  private var contentHeight: CGFloat { rowSpans.last?.bottom ?? 0 }

  func update(lines: [NumberedLine], gutter: DiffGutter) {
    guard lines != self.lines || gutter != self.gutter else { return }
    self.lines = lines
    self.gutter = gutter
    applyText()
  }

  func height(forWidth width: CGFloat) -> CGFloat {
    measure(width: width)
    return contentHeight
  }

  override func layout() {
    super.layout()
    measure(width: bounds.width)
    textView.frame = NSRect(
      x: gutter.textColumnX, y: 0, width: max(gutter.textWidth(forRowWidth: bounds.width), 0),
      height: contentHeight)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    guard let storage = textView.textStorage else { return }
    storage.addAttribute(
      .foregroundColor, value: DiffRunPalette(appearance: effectiveAppearance).text,
      range: NSRange(location: 0, length: storage.length))
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let palette = DiffRunPalette(appearance: effectiveAppearance)
    for (line, span) in zip(lines, rowSpans)
    where span.bottom > dirtyRect.minY && span.top < dirtyRect.maxY {
      if let fill = palette.background(for: line.kind) {
        fill.setFill()
        NSRect(x: 0, y: span.top, width: bounds.width, height: span.bottom - span.top)
          .fill(using: .sourceOver)
      }
      drawGutter(for: line, top: span.top + Self.rowPadding, palette: palette)
    }
  }

  private func configureTextView() {
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = false
    textView.drawsBackground = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = false
    textView.textContainerInset = NSSize(width: 0, height: Self.rowPadding)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.heightTracksTextView = false
  }

  private func applyText() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.paragraphSpacing = Self.rowPadding * 2
    let text = NSAttributedString(
      string: lines.map { $0.text + "\n" }.joined(),
      attributes: [
        .font: Self.codeFont,
        .foregroundColor: DiffRunPalette(appearance: effectiveAppearance).text,
        .paragraphStyle: paragraph,
      ])
    textView.textStorage?.setAttributedString(text)
    rowEndOffsets = Self.rowEndOffsets(of: lines)
    measuredWidth = nil
    rowSpans = []
    invalidateIntrinsicContentSize()
    needsLayout = true
    needsDisplay = true
  }

  private func measure(width: CGFloat) {
    guard measuredWidth != width else { return }
    measuredWidth = width
    let textWidth = gutter.textWidth(forRowWidth: width)
    guard textWidth > 0, let layoutManager = textView.textLayoutManager else {
      rowSpans = []
      return
    }
    textView.textContainer?.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
    layoutManager.invalidateLayout(for: layoutManager.documentRange)
    rowSpans = layOutRows(in: layoutManager)
  }

  private func layOutRows(in layoutManager: NSTextLayoutManager) -> [DiffRowSpan] {
    let originY = textView.textContainerOrigin.y
    let rowEnds = rowEndOffsets
    let documentStart = layoutManager.documentRange.location
    var laidOutSpans: [DiffRowSpan?] = Array(repeating: nil, count: rowEnds.count)
    var row = 0
    layoutManager.enumerateTextLayoutFragments(from: documentStart, options: [.ensuresLayout]) {
      fragment in
      let fragmentStart = layoutManager.offset(
        from: documentStart, to: fragment.rangeInElement.location)
      while row < rowEnds.count, fragmentStart >= rowEnds[row] {
        row += 1
      }
      guard row < rowEnds.count else { return false }
      let lineFragments = Self.contentLineFragments(of: fragment)
      guard let first = lineFragments.first, let last = lineFragments.last else { return true }
      let fragmentY = originY + fragment.layoutFragmentFrame.minY
      let top = fragmentY + first.typographicBounds.minY - Self.rowPadding
      let bottom = fragmentY + last.typographicBounds.maxY + Self.rowPadding
      laidOutSpans[row] = DiffRowSpan(top: laidOutSpans[row]?.top ?? top, bottom: bottom)
      return true
    }
    var spans: [DiffRowSpan] = []
    spans.reserveCapacity(laidOutSpans.count)
    for laidOutSpan in laidOutSpans {
      let previousBottom = spans.last?.bottom ?? 0
      spans.append(laidOutSpan ?? DiffRowSpan(top: previousBottom, bottom: previousBottom))
    }
    return spans
  }

  private static func rowEndOffsets(of lines: [NumberedLine]) -> [Int] {
    var end = 0
    return lines.map { line in
      end += line.text.utf16.count + 1
      return end
    }
  }

  private static func contentLineFragments(of fragment: NSTextLayoutFragment)
    -> [NSTextLineFragment]
  {
    let lineFragments = fragment.textLineFragments
    guard lineFragments.count > 1, let last = lineFragments.last, last.characterRange.length == 0
    else {
      return lineFragments
    }
    return Array(lineFragments.dropLast())
  }

  private func drawGutter(for line: NumberedLine, top: CGFloat, palette: DiffRunPalette) {
    if gutter == .numbered {
      drawNumber(
        line.oldNumber, columnMaxX: DiffGutter.horizontalPadding + DiffGutter.numberColumnWidth,
        top: top, palette: palette)
      drawNumber(
        line.newNumber,
        columnMaxX: DiffGutter.horizontalPadding + DiffGutter.numberColumnWidth * 2, top: top,
        palette: palette)
    }
    guard let marker = Self.marker(for: line.kind) else { return }
    let string = NSAttributedString(
      string: marker, attributes: [.font: Self.codeFont, .foregroundColor: palette.text])
    let x = gutter.markerColumnX + (DiffGutter.markerColumnWidth - string.size().width) / 2
    string.draw(at: NSPoint(x: x, y: top))
  }

  private func drawNumber(
    _ number: Int?, columnMaxX: CGFloat, top: CGFloat, palette: DiffRunPalette
  ) {
    guard let number else { return }
    let string = NSAttributedString(
      string: String(number),
      attributes: [.font: Self.numberFont, .foregroundColor: palette.gutter]
    )
    string.draw(at: NSPoint(x: columnMaxX - string.size().width, y: top))
  }

  private static func marker(for kind: NumberedLineKind) -> String? {
    switch kind {
    case .added: return "+"
    case .removed: return "-"
    case .context: return nil
    }
  }
}
