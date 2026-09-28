import Foundation

enum JSONEditError: Error, Equatable, Sendable {
  case notAContainer
  case childOutOfRange
}

struct JSONSourceDocument: Sendable {
  private(set) var bytes: [UInt8]
  private(set) var root: JSONSpanNode
  let layout: JSONLayout

  init(bytes: [UInt8]) throws {
    let root = try JSONSpanReader.parse(bytes)
    self.bytes = bytes
    self.root = root
    self.layout = JSONLayout.detect(in: bytes, root: root)
  }

  func lineIndent(at offset: Int) -> String {
    JSONLayout.lineIndent(in: bytes, at: offset)
  }

  mutating func replace(_ range: Range<Int>, with text: String) throws {
    var updated = bytes
    updated.replaceSubrange(range, with: Array(text.utf8))
    root = try JSONSpanReader.parse(updated)
    bytes = updated
  }

  mutating func replaceValue(_ node: JSONSpanNode, with fragment: JSONFragment) throws {
    let indent = lineIndent(at: node.range.lowerBound)
    try replace(node.range, with: layout.render(fragment, indent: indent))
  }

  mutating func appendMember(_ member: JSONFragmentMember, to object: JSONSpanNode) throws {
    guard let members = object.members else { throw JSONEditError.notAContainer }
    let layout = layout
    try appendChild(to: object, after: members.map(\.range)) { indent in
      layout.memberText(member, indent: indent)
    }
  }

  mutating func appendElement(_ element: JSONFragment, to array: JSONSpanNode) throws {
    guard let elements = array.elements else { throw JSONEditError.notAContainer }
    let layout = layout
    try appendChild(to: array, after: elements.map(\.range)) { indent in
      layout.render(element, indent: indent)
    }
  }

  mutating func removeMember(at index: Int, from object: JSONSpanNode) throws {
    guard let members = object.members else { throw JSONEditError.notAContainer }
    try removeChild(at: index, from: object, children: members.map(\.range))
  }

  mutating func removeElement(at index: Int, from array: JSONSpanNode) throws {
    guard let elements = array.elements else { throw JSONEditError.notAContainer }
    try removeChild(at: index, from: array, children: elements.map(\.range))
  }

  private func interior(of container: JSONSpanNode) -> Range<Int> {
    (container.range.lowerBound + 1)..<(container.range.upperBound - 1)
  }

  private func whitespace(before offset: Int) -> ArraySlice<UInt8> {
    var start = offset
    while start > 0, JSONByte.isWhitespace(bytes[start - 1]) {
      start -= 1
    }
    return bytes[start..<offset]
  }

  private mutating func appendChild(
    to container: JSONSpanNode, after children: [Range<Int>], render: (String) -> String
  ) throws {
    guard let last = children.last else {
      let indent = lineIndent(at: container.range.lowerBound)
      let inner = indent + layout.indentUnit
      let text = layout.newline + inner + render(inner) + layout.newline + indent
      try replace(interior(of: container), with: text)
      return
    }
    let indent = lineIndent(at: last.lowerBound)
    let gap = whitespace(before: last.lowerBound)
    let separator =
      gap.contains(JSONByte.lineFeed)
      ? layout.newline + indent : String(decoding: gap, as: UTF8.self)
    try replace(last.upperBound..<last.upperBound, with: "," + separator + render(indent))
  }

  private mutating func removeChild(
    at index: Int, from container: JSONSpanNode, children: [Range<Int>]
  ) throws {
    guard children.indices.contains(index) else { throw JSONEditError.childOutOfRange }
    if children.count == 1 {
      try replace(interior(of: container), with: "")
    } else if index < children.count - 1 {
      try replace(children[index].lowerBound..<children[index + 1].lowerBound, with: "")
    } else {
      try replace(children[index - 1].upperBound..<children[index].upperBound, with: "")
    }
  }
}
