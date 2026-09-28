import Foundation

public struct CodexTrustTable: Sendable, Equatable {
  public let trustedHashes: [String: String]

  public init(trustedHashes: [String: String]) {
    self.trustedHashes = trustedHashes
  }

  public init?(configBytes: [UInt8]) {
    guard let text = String(data: Data(configBytes), encoding: .utf8) else { return nil }
    var scanner = CodexTrustScanner(scalars: Array(text.unicodeScalars))
    guard let hashes = try? scanner.scan() else { return nil }
    self.trustedHashes = hashes
  }

  public static func read(_ file: Doctor.FileState) -> CodexTrustTable? {
    guard case .bytes(let bytes) = file else { return nil }
    return CodexTrustTable(configBytes: bytes)
  }
}

private struct CodexTrustScanner {
  enum KeyForm {
    case bare
    case basic
    case literal
  }

  struct KeyPart {
    let value: String
    let form: KeyForm
  }

  enum Table {
    case root
    case hooks
    case hooksState
    case hookState(String)
    case unrelated
  }

  struct CannotTell: Error {}

  let scalars: [Unicode.Scalar]
  var index = 0
  var table = Table.root
  var hashes: [String: String] = [:]
  var hookKeys: Set<String> = []

  mutating func scan() throws -> [String: String] {
    skipBlanks()
    while let scalar = peek() {
      switch scalar {
      case "\n", "\r", "#":
        try endLine()
      case "[":
        try readHeader()
      default:
        try readKeyValue()
      }
      skipBlanks()
    }
    return hashes
  }

  private mutating func readHeader() throws {
    index += 1
    let isArray = peek() == "["
    if isArray {
      index += 1
    }
    skipBlanks()
    let key = try readDottedKey()
    try consume("]")
    if isArray {
      try consume("]")
    }
    try endLine()
    table = try tableNamed(key, isArray: isArray)
  }

  private mutating func tableNamed(_ key: [KeyPart], isArray: Bool) throws -> Table {
    let names = key.map(\.value)
    guard names.first == "hooks" else { return .unrelated }
    guard names.count > 1 else {
      guard !isArray else { throw CannotTell() }
      return .hooks
    }
    guard names[1] == "state" else { return .unrelated }
    guard !isArray, names.count <= 3 else { throw CannotTell() }
    guard names.count == 3 else { return .hooksState }
    guard key[2].form == .basic, hookKeys.insert(names[2]).inserted else { throw CannotTell() }
    return .hookState(names[2])
  }

  private mutating func readKeyValue() throws {
    let names = try readDottedKey().map(\.value)
    try consume("=")
    skipBlanks()
    switch table {
    case .root:
      if names.first == "hooks", names.count == 1 || names[1] == "state" { throw CannotTell() }
    case .hooks:
      if names.first == "state" { throw CannotTell() }
    case .hooksState:
      throw CannotTell()
    case .hookState(let hookKey):
      if names.first == "trusted_hash" {
        guard names.count == 1, hashes[hookKey] == nil, peek() == "\"", !startsTriple("\"")
        else { throw CannotTell() }
        hashes[hookKey] = try readBasicString()
        try endLine()
        return
      }
    case .unrelated:
      break
    }
    try skipValue()
    try endLine()
  }

  private mutating func readDottedKey() throws -> [KeyPart] {
    var parts = [try readSimpleKey()]
    skipBlanks()
    while peek() == "." {
      index += 1
      skipBlanks()
      parts.append(try readSimpleKey())
      skipBlanks()
    }
    return parts
  }

  private mutating func readSimpleKey() throws -> KeyPart {
    guard let scalar = peek() else { throw CannotTell() }
    if scalar == "\"" || scalar == "'" {
      guard !startsTriple(scalar) else { throw CannotTell() }
      return scalar == "\""
        ? KeyPart(value: try readBasicString(), form: .basic)
        : KeyPart(value: try readLiteralString(), form: .literal)
    }
    let start = index
    while let next = peek(), isBareKeyScalar(next) {
      index += 1
    }
    guard index > start else { throw CannotTell() }
    return KeyPart(value: text(scalars[start..<index]), form: .bare)
  }

  private mutating func readBasicString() throws -> String {
    index += 1
    var value = String.UnicodeScalarView()
    while let scalar = peek() {
      index += 1
      switch scalar {
      case "\"":
        return String(value)
      case "\\":
        value.append(try readEscape())
      case "\n", "\r":
        throw CannotTell()
      default:
        value.append(scalar)
      }
    }
    throw CannotTell()
  }

  private mutating func readEscape() throws -> Unicode.Scalar {
    guard let scalar = peek() else { throw CannotTell() }
    index += 1
    switch scalar {
    case "\"", "\\":
      return scalar
    case "b":
      return "\u{8}"
    case "t":
      return "\t"
    case "n":
      return "\n"
    case "f":
      return "\u{C}"
    case "r":
      return "\r"
    case "u":
      return try readHexScalar(digits: 4)
    case "U":
      return try readHexScalar(digits: 8)
    default:
      throw CannotTell()
    }
  }

  private mutating func readHexScalar(digits: Int) throws -> Unicode.Scalar {
    guard index + digits <= scalars.count else { throw CannotTell() }
    let hex = scalars[index..<(index + digits)]
    guard hex.allSatisfy(\.properties.isASCIIHexDigit),
      let code = UInt32(text(hex), radix: 16),
      let scalar = Unicode.Scalar(code)
    else { throw CannotTell() }
    index += digits
    return scalar
  }

  private mutating func readLiteralString() throws -> String {
    index += 1
    let start = index
    while let scalar = peek() {
      if scalar == "'" {
        index += 1
        return text(scalars[start..<(index - 1)])
      }
      guard scalar != "\n", scalar != "\r" else { throw CannotTell() }
      index += 1
    }
    throw CannotTell()
  }

  private mutating func skipValue() throws {
    guard let scalar = peek() else { throw CannotTell() }
    switch scalar {
    case "\"", "'":
      try skipString(scalar)
    case "[", "{":
      try skipNested()
    case "\n", "\r", "#":
      throw CannotTell()
    default:
      while let next = peek(), next != "\n", next != "\r", next != "#" {
        index += 1
      }
    }
  }

  private mutating func skipString(_ quote: Unicode.Scalar) throws {
    if startsTriple(quote) {
      try skipMultilineString(quote: quote)
      return
    }
    index += 1
    while let scalar = peek(), scalar != quote {
      guard scalar != "\n", scalar != "\r" else { throw CannotTell() }
      index += quote == "\"" && scalar == "\\" ? 2 : 1
    }
    guard peek() == quote else { throw CannotTell() }
    index += 1
  }

  private mutating func skipMultilineString(quote: Unicode.Scalar) throws {
    index += 3
    while let scalar = peek() {
      guard scalar == quote else {
        index += quote == "\"" && scalar == "\\" ? 2 : 1
        continue
      }
      var run = 0
      while peek() == quote {
        run += 1
        index += 1
      }
      if run >= 3 {
        guard run <= 5 else { throw CannotTell() }
        return
      }
    }
    throw CannotTell()
  }

  private mutating func skipNested() throws {
    var closers: [Unicode.Scalar] = []
    repeat {
      guard let scalar = peek() else { throw CannotTell() }
      switch scalar {
      case "[":
        closers.append("]")
        index += 1
      case "{":
        closers.append("}")
        index += 1
      case "]", "}":
        guard closers.popLast() == scalar else { throw CannotTell() }
        index += 1
      case "\"", "'":
        try skipString(scalar)
      case "#":
        skipComment()
      default:
        index += 1
      }
    } while !closers.isEmpty
  }

  private mutating func endLine() throws {
    skipBlanks()
    if peek() == "#" {
      skipComment()
    }
    guard let scalar = peek() else { return }
    if scalar == "\r" {
      index += 1
      guard peek() == "\n" else { throw CannotTell() }
    } else if scalar != "\n" {
      throw CannotTell()
    }
    index += 1
  }

  private mutating func consume(_ expected: Unicode.Scalar) throws {
    skipBlanks()
    guard peek() == expected else { throw CannotTell() }
    index += 1
  }

  private mutating func skipBlanks() {
    while let scalar = peek(), scalar == " " || scalar == "\t" {
      index += 1
    }
  }

  private mutating func skipComment() {
    while let scalar = peek(), scalar != "\n", scalar != "\r" {
      index += 1
    }
  }

  private func peek() -> Unicode.Scalar? {
    index < scalars.count ? scalars[index] : nil
  }

  private func startsTriple(_ quote: Unicode.Scalar) -> Bool {
    index + 2 < scalars.count && scalars[index..<(index + 3)].allSatisfy { $0 == quote }
  }

  private func isBareKeyScalar(_ scalar: Unicode.Scalar) -> Bool {
    ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
      || scalar == "_" || scalar == "-"
  }

  private func text(_ slice: ArraySlice<Unicode.Scalar>) -> String {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: slice)
    return String(view)
  }
}
