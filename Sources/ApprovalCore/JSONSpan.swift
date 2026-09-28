import Foundation

struct JSONSpanError: Error, Equatable, Sendable, CustomStringConvertible {
  let line: Int
  let column: Int

  var description: String {
    "not valid JSON at line \(line), column \(column)"
  }

  init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }

  init(bytes: [UInt8], offset: Int) {
    let prefix = bytes[..<min(offset, bytes.count)]
    let lineStart = prefix.lastIndex(of: JSONByte.lineFeed).map { $0 + 1 } ?? 0
    self.init(
      line: prefix.filter { $0 == JSONByte.lineFeed }.count + 1,
      column: prefix.count - lineStart + 1)
  }
}

struct JSONSpanMember: Sendable, Equatable {
  let key: String
  let keyRange: Range<Int>
  let value: JSONSpanNode

  var range: Range<Int> {
    keyRange.lowerBound..<value.range.upperBound
  }
}

enum JSONSpanContent: Sendable, Equatable {
  case object([JSONSpanMember])
  case array([JSONSpanNode])
  case string(String)
  case number(String)
  case bool(Bool)
  case null
}

struct JSONSpanNode: Sendable, Equatable {
  let content: JSONSpanContent
  let range: Range<Int>

  var members: [JSONSpanMember]? {
    guard case .object(let members) = content else { return nil }
    return members
  }

  var elements: [JSONSpanNode]? {
    guard case .array(let elements) = content else { return nil }
    return elements
  }

  var stringValue: String? {
    guard case .string(let value) = content else { return nil }
    return value
  }

  var numberValue: Double? {
    guard case .number(let spelling) = content else { return nil }
    return Double(spelling)
  }

  func member(named key: String) -> JSONSpanMember? {
    members?.last { $0.key == key }
  }

  func memberIndex(named key: String) -> Int? {
    members?.lastIndex { $0.key == key }
  }
}

enum JSONByte {
  static let space = UInt8(ascii: " ")
  static let tab = UInt8(ascii: "\t")
  static let lineFeed = UInt8(ascii: "\n")
  static let carriageReturn = UInt8(ascii: "\r")
  static let quote = UInt8(ascii: "\"")
  static let backslash = UInt8(ascii: "\\")
  static let colon = UInt8(ascii: ":")
  static let comma = UInt8(ascii: ",")

  static func isWhitespace(_ byte: UInt8) -> Bool {
    byte == space || byte == tab || byte == lineFeed || byte == carriageReturn
  }
}

struct JSONSpanReader {
  static let maximumDepth = 64
  static let replacementScalar: Unicode.Scalar = "\u{FFFD}"

  private let bytes: [UInt8]
  private var offset: Int

  static func parse(_ bytes: [UInt8]) throws -> JSONSpanNode {
    var reader = JSONSpanReader(bytes: bytes, offset: 0)
    reader.skipWhitespace()
    let root = try reader.readValue(depth: 0)
    reader.skipWhitespace()
    guard reader.offset == bytes.count else { throw reader.failure() }
    return root
  }

  private func peek(at position: Int? = nil) -> UInt8? {
    let index = position ?? offset
    guard index < bytes.count else { return nil }
    return bytes[index]
  }

  private func failure() -> JSONSpanError {
    JSONSpanError(bytes: bytes, offset: offset)
  }

  private mutating func skipWhitespace() {
    while let byte = peek(), JSONByte.isWhitespace(byte) {
      offset += 1
    }
  }

  private mutating func readValue(depth: Int) throws -> JSONSpanNode {
    guard depth < Self.maximumDepth, let byte = peek() else { throw failure() }
    switch byte {
    case UInt8(ascii: "{"):
      return try readObject(depth: depth)
    case UInt8(ascii: "["):
      return try readArray(depth: depth)
    case JSONByte.quote:
      let start = offset
      let string = try readString()
      return JSONSpanNode(content: .string(string), range: start..<offset)
    case UInt8(ascii: "t"):
      return try readLiteral("true", content: .bool(true))
    case UInt8(ascii: "f"):
      return try readLiteral("false", content: .bool(false))
    case UInt8(ascii: "n"):
      return try readLiteral("null", content: .null)
    default:
      return try readNumber()
    }
  }

  private mutating func readObject(depth: Int) throws -> JSONSpanNode {
    let start = offset
    offset += 1
    var members: [JSONSpanMember] = []
    skipWhitespace()
    if peek() == UInt8(ascii: "}") {
      offset += 1
      return JSONSpanNode(content: .object(members), range: start..<offset)
    }
    while true {
      guard peek() == JSONByte.quote else { throw failure() }
      let keyStart = offset
      let key = try readString()
      let keyRange = keyStart..<offset
      skipWhitespace()
      guard peek() == JSONByte.colon else { throw failure() }
      offset += 1
      skipWhitespace()
      let value = try readValue(depth: depth + 1)
      members.append(JSONSpanMember(key: key, keyRange: keyRange, value: value))
      skipWhitespace()
      switch peek() {
      case JSONByte.comma:
        offset += 1
        skipWhitespace()
      case UInt8(ascii: "}"):
        offset += 1
        return JSONSpanNode(content: .object(members), range: start..<offset)
      default:
        throw failure()
      }
    }
  }

  private mutating func readArray(depth: Int) throws -> JSONSpanNode {
    let start = offset
    offset += 1
    var elements: [JSONSpanNode] = []
    skipWhitespace()
    if peek() == UInt8(ascii: "]") {
      offset += 1
      return JSONSpanNode(content: .array(elements), range: start..<offset)
    }
    while true {
      elements.append(try readValue(depth: depth + 1))
      skipWhitespace()
      switch peek() {
      case JSONByte.comma:
        offset += 1
        skipWhitespace()
      case UInt8(ascii: "]"):
        offset += 1
        return JSONSpanNode(content: .array(elements), range: start..<offset)
      default:
        throw failure()
      }
    }
  }

  private mutating func readLiteral(_ word: String, content: JSONSpanContent) throws
    -> JSONSpanNode
  {
    let start = offset
    for expected in word.utf8 {
      guard peek() == expected else { throw failure() }
      offset += 1
    }
    return JSONSpanNode(content: content, range: start..<offset)
  }

  private mutating func readNumber() throws -> JSONSpanNode {
    let start = offset
    if peek() == UInt8(ascii: "-") {
      offset += 1
    }
    if peek() == UInt8(ascii: "0") {
      offset += 1
    } else {
      try readDigits()
    }
    if peek() == UInt8(ascii: ".") {
      offset += 1
      try readDigits()
    }
    if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
      offset += 1
      if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") {
        offset += 1
      }
      try readDigits()
    }
    let spelling = String(decoding: bytes[start..<offset], as: UTF8.self)
    return JSONSpanNode(content: .number(spelling), range: start..<offset)
  }

  private mutating func readDigits() throws {
    guard let first = peek(), Self.isDigit(first) else { throw failure() }
    while let byte = peek(), Self.isDigit(byte) {
      offset += 1
    }
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
  }

  private mutating func readString() throws -> String {
    guard peek() == JSONByte.quote else { throw failure() }
    offset += 1
    var scalars = String.UnicodeScalarView()
    while true {
      guard let byte = peek() else { throw failure() }
      switch byte {
      case JSONByte.quote:
        offset += 1
        return String(scalars)
      case JSONByte.backslash:
        scalars.append(try readEscape())
      case 0..<0x20:
        throw failure()
      default:
        scalars.append(try readUTF8Scalar())
      }
    }
  }

  private mutating func readEscape() throws -> Unicode.Scalar {
    offset += 1
    guard let byte = peek() else { throw failure() }
    offset += 1
    switch byte {
    case JSONByte.quote: return "\""
    case JSONByte.backslash: return "\\"
    case UInt8(ascii: "/"): return "/"
    case UInt8(ascii: "b"): return "\u{08}"
    case UInt8(ascii: "f"): return "\u{0C}"
    case UInt8(ascii: "n"): return "\n"
    case UInt8(ascii: "r"): return "\r"
    case UInt8(ascii: "t"): return "\t"
    case UInt8(ascii: "u"): return try readUnicodeEscape()
    default: throw failure()
    }
  }

  private mutating func readUnicodeEscape() throws -> Unicode.Scalar {
    let high = try readHexQuad()
    if (0xD800...0xDBFF).contains(high), peek() == JSONByte.backslash,
      peek(at: offset + 1) == UInt8(ascii: "u")
    {
      let resume = offset
      offset += 2
      let low = try readHexQuad()
      if (0xDC00...0xDFFF).contains(low) {
        let combined = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
        return Unicode.Scalar(combined) ?? Self.replacementScalar
      }
      offset = resume
    }
    return Unicode.Scalar(high) ?? Self.replacementScalar
  }

  private mutating func readHexQuad() throws -> UInt32 {
    var value: UInt32 = 0
    for _ in 0..<4 {
      guard let byte = peek(), let digit = Self.hexValue(byte) else { throw failure() }
      value = value * 16 + digit
      offset += 1
    }
    return value
  }

  private static func hexValue(_ byte: UInt8) -> UInt32? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(byte - UInt8(ascii: "0"))
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return UInt32(byte - UInt8(ascii: "a") + 10)
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return UInt32(byte - UInt8(ascii: "A") + 10)
    default: return nil
    }
  }

  private mutating func readUTF8Scalar() throws -> Unicode.Scalar {
    guard let lead = peek() else { throw failure() }
    let length: Int
    let minimum: UInt32
    var value: UInt32
    switch lead {
    case 0x00...0x7F:
      length = 1
      minimum = 0
      value = UInt32(lead)
    case 0xC2...0xDF:
      length = 2
      minimum = 0x80
      value = UInt32(lead & 0x1F)
    case 0xE0...0xEF:
      length = 3
      minimum = 0x800
      value = UInt32(lead & 0x0F)
    case 0xF0...0xF4:
      length = 4
      minimum = 0x10000
      value = UInt32(lead & 0x07)
    default:
      throw failure()
    }
    guard offset + length <= bytes.count else { throw failure() }
    for position in (offset + 1)..<(offset + length) {
      let continuation = bytes[position]
      guard continuation & 0xC0 == 0x80 else { throw failure() }
      value = (value << 6) | UInt32(continuation & 0x3F)
    }
    guard value >= minimum, let scalar = Unicode.Scalar(value) else { throw failure() }
    offset += length
    return scalar
  }
}
