import Foundation

struct TextLine: Sendable, Equatable {
  let text: String
  let endsWithNewline: Bool

  static func split(_ content: String) -> [TextLine] {
    guard !content.isEmpty else { return [] }
    let endsWithNewline = content.unicodeScalars.last == "\n"
    var pieces = content.components(separatedBy: "\n")
    if endsWithNewline {
      pieces.removeLast()
    }
    let lastIndex = pieces.count - 1
    return pieces.enumerated().map { index, piece in
      TextLine(
        text: piece.hasSuffix("\r") ? String(piece.dropLast()) : piece,
        endsWithNewline: index < lastIndex || endsWithNewline)
    }
  }
}
