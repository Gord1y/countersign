import Foundation

enum JSONFragment: Sendable, Equatable {
  case object([JSONFragmentMember])
  case array([JSONFragment])
  case string(String)
  case integer(Int)
  case number(String)
  case bool(Bool)
}

struct JSONFragmentMember: Sendable, Equatable {
  let key: String
  let value: JSONFragment
}

struct JSONLayout: Sendable, Equatable {
  let indentUnit: String
  let newline: String
  let beforeColon: String
  let afterColon: String

  static let standard = JSONLayout(
    indentUnit: "  ", newline: "\n", beforeColon: "", afterColon: " ")

  static func detect(in bytes: [UInt8], root: JSONSpanNode) -> JSONLayout {
    let spacing = colonSpacing(in: bytes, root: root)
    return JSONLayout(
      indentUnit: indentUnit(in: bytes, node: root) ?? standard.indentUnit,
      newline: newline(in: bytes),
      beforeColon: spacing?.before ?? standard.beforeColon,
      afterColon: spacing?.after ?? standard.afterColon)
  }

  static func lineIndent(in bytes: [UInt8], at offset: Int) -> String {
    var start = min(offset, bytes.count)
    while start > 0, bytes[start - 1] != JSONByte.lineFeed {
      start -= 1
    }
    var end = start
    while end < bytes.count, bytes[end] == JSONByte.space || bytes[end] == JSONByte.tab {
      end += 1
    }
    return String(decoding: bytes[start..<end], as: UTF8.self)
  }

  static func quoted(_ text: String) -> String {
    "\"" + escaped(text) + "\""
  }

  static func escaped(_ text: String) -> String {
    var result = ""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case "\u{08}": result += "\\b"
      case "\u{0C}": result += "\\f"
      case "\u{00}"..."\u{1F}":
        let hex = String(scalar.value, radix: 16)
        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  func render(_ fragment: JSONFragment, indent: String) -> String {
    let inner = indent + indentUnit
    switch fragment {
    case .string(let value):
      return Self.quoted(value)
    case .integer(let value):
      return String(value)
    case .number(let spelling):
      return spelling
    case .bool(let value):
      return value ? "true" : "false"
    case .array(let elements):
      guard !elements.isEmpty else { return "[]" }
      let lines = elements.map { inner + render($0, indent: inner) }
      return "[" + newline + lines.joined(separator: "," + newline) + newline + indent + "]"
    case .object(let members):
      guard !members.isEmpty else { return "{}" }
      let lines = members.map { inner + memberText($0, indent: inner) }
      return "{" + newline + lines.joined(separator: "," + newline) + newline + indent + "}"
    }
  }

  func memberText(_ member: JSONFragmentMember, indent: String) -> String {
    Self.quoted(member.key) + beforeColon + ":" + afterColon + render(member.value, indent: indent)
  }

  private static func newline(in bytes: [UInt8]) -> String {
    guard let index = bytes.firstIndex(of: JSONByte.lineFeed) else { return standard.newline }
    return index > 0 && bytes[index - 1] == JSONByte.carriageReturn ? "\r\n" : "\n"
  }

  private static func colonSpacing(in bytes: [UInt8], root: JSONSpanNode) -> (
    before: String, after: String
  )? {
    guard let member = firstMember(in: root) else { return nil }
    let gap = Array(bytes[member.keyRange.upperBound..<member.value.range.lowerBound])
    guard let colon = gap.firstIndex(of: JSONByte.colon) else { return nil }
    let before = gap[..<colon]
    let after = gap[(colon + 1)...]
    let breaksLine = gap.contains(JSONByte.lineFeed) || gap.contains(JSONByte.carriageReturn)
    guard !breaksLine else { return nil }
    return (
      before: String(decoding: before, as: UTF8.self),
      after: String(decoding: after, as: UTF8.self)
    )
  }

  private static func firstMember(in node: JSONSpanNode) -> JSONSpanMember? {
    switch node.content {
    case .object(let members):
      return members.first
    case .array(let elements):
      return elements.lazy.compactMap { firstMember(in: $0) }.first
    default:
      return nil
    }
  }

  private static func indentUnit(in bytes: [UInt8], node: JSONSpanNode) -> String? {
    let childStarts: [Int]
    let childNodes: [JSONSpanNode]
    switch node.content {
    case .object(let members):
      childStarts = members.map(\.keyRange.lowerBound)
      childNodes = members.map(\.value)
    case .array(let elements):
      childStarts = elements.map(\.range.lowerBound)
      childNodes = elements
    default:
      return nil
    }
    if let firstStart = childStarts.first,
      bytes[node.range.lowerBound..<firstStart].contains(JSONByte.lineFeed)
    {
      let outer = lineIndent(in: bytes, at: node.range.lowerBound)
      let inner = lineIndent(in: bytes, at: firstStart)
      if inner.hasPrefix(outer), inner.count > outer.count {
        return String(inner.dropFirst(outer.count))
      }
    }
    return childNodes.lazy.compactMap { indentUnit(in: bytes, node: $0) }.first
  }
}
