import Foundation

struct Diagnostic {
  let file: String
  let line: Int
  let message: String
}

final class Diagnostics {
  private(set) var items: [Diagnostic] = []

  func add(_ file: String, _ line: Int, _ message: String) {
    items.append(Diagnostic(file: file, line: line, message: message))
  }

  var isEmpty: Bool { items.isEmpty }
}

enum ScalarToken {
  case plain(String)
  case singleQuoted(String)
  case doubleQuoted(String)

  var value: String {
    switch self {
    case .plain(let s): return s
    case .singleQuoted(let s): return s
    case .doubleQuoted(let s): return s
    }
  }

  var isUnquotedTrue: Bool {
    if case .plain(let s) = self { return s == "true" }
    return false
  }

  var isUnquotedFalse: Bool {
    if case .plain(let s) = self { return s == "false" }
    return false
  }
}

func unescapeDoubleQuoted(_ s: Substring) -> String? {
  var result = ""
  var iterator = s.makeIterator()
  while let ch = iterator.next() {
    if ch == "\\" {
      guard let next = iterator.next() else { return nil }
      switch next {
      case "\"": result.append("\"")
      case "\\": result.append("\\")
      case "n": result.append("\n")
      case "t": result.append("\t")
      default: return nil
      }
    } else {
      result.append(ch)
    }
  }
  return result
}

func parseScalarToken(_ raw: Substring) -> ScalarToken? {
  let trimmed = raw.trimmingCharacters(in: .whitespaces)
  if trimmed.isEmpty { return nil }
  if trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" {
    let inner = trimmed.dropFirst().dropLast()
    guard let unescaped = unescapeDoubleQuoted(inner) else { return nil }
    return .doubleQuoted(unescaped)
  }
  if trimmed.count >= 2, trimmed.first == "'", trimmed.last == "'" {
    let inner = trimmed.dropFirst().dropLast()
    return .singleQuoted(inner.replacingOccurrences(of: "''", with: "'"))
  }
  if trimmed.first == "\"" || trimmed.first == "'" { return nil }
  return .plain(trimmed)
}

func leadingSpaces(_ line: Substring) -> Int {
  var count = 0
  for ch in line {
    if ch == " " {
      count += 1
    } else {
      break
    }
  }
  return count
}

func splitKeyValue(_ line: Substring) -> (key: String, rest: Substring)? {
  guard let colon = line.firstIndex(of: ":") else { return nil }
  let key = line[line.startIndex..<colon]
  guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
  let rest = line[line.index(after: colon)...]
  return (String(key), rest)
}

enum FrontmatterValue {
  case scalar(ScalarToken)
  case list([ScalarToken])
  case map([String: ScalarToken])
}

struct Frontmatter {
  var values: [String: FrontmatterValue] = [:]
  var lines: [String: Int] = [:]
}

func parseFrontmatter(
  path: String, lines: [Substring], startLine: Int, diagnostics: Diagnostics
) -> Frontmatter {
  var frontmatter = Frontmatter()
  var i = 0
  while i < lines.count {
    let line = lines[i]
    let lineNo = startLine + i
    if line.trimmingCharacters(in: .whitespaces).isEmpty {
      i += 1
      continue
    }
    if leadingSpaces(line) != 0 {
      diagnostics.add(path, lineNo, "unexpected indentation")
      i += 1
      continue
    }
    guard let (key, rest) = splitKeyValue(line) else {
      diagnostics.add(path, lineNo, "expected 'key: value'")
      i += 1
      continue
    }
    if frontmatter.values[key] != nil {
      diagnostics.add(path, lineNo, "duplicate field '\(key)'")
    }
    let trimmedRest = rest.trimmingCharacters(in: .whitespaces)
    if trimmedRest.isEmpty {
      var j = i + 1
      var listItems: [ScalarToken] = []
      var mapItems: [String: ScalarToken] = [:]
      var isList = false
      var isMap = false
      while j < lines.count {
        let subline = lines[j]
        if subline.trimmingCharacters(in: .whitespaces).isEmpty {
          j += 1
          continue
        }
        let subLeading = leadingSpaces(subline)
        if subLeading == 0 { break }
        if subLeading != 2 {
          diagnostics.add(path, startLine + j, "unexpected indentation")
          j += 1
          continue
        }
        let content = subline.dropFirst(2)
        if content == "-" || content.hasPrefix("- ") {
          isList = true
          let itemRaw = content == "-" ? Substring("") : content.dropFirst(2)
          guard let token = parseScalarToken(itemRaw) else {
            diagnostics.add(path, startLine + j, "unsupported list item syntax")
            j += 1
            continue
          }
          listItems.append(token)
        } else if let (subkey, subrest) = splitKeyValue(content) {
          isMap = true
          guard let token = parseScalarToken(subrest) else {
            diagnostics.add(path, startLine + j, "unsupported value syntax for '\(subkey)'")
            j += 1
            continue
          }
          mapItems[subkey] = token
        } else {
          diagnostics.add(path, startLine + j, "unsupported YAML syntax")
        }
        j += 1
      }
      if isList && isMap {
        diagnostics.add(path, lineNo, "field '\(key)' mixes a list and a map")
      } else if isList {
        frontmatter.values[key] = .list(listItems)
      } else if isMap {
        frontmatter.values[key] = .map(mapItems)
      } else {
        frontmatter.values[key] = .list([])
      }
      frontmatter.lines[key] = lineNo
      i = j
    } else {
      guard let token = parseScalarToken(rest) else {
        diagnostics.add(path, lineNo, "unsupported value syntax for '\(key)'")
        i += 1
        continue
      }
      frontmatter.values[key] = .scalar(token)
      frontmatter.lines[key] = lineNo
      i += 1
    }
  }
  return frontmatter
}

struct ReleaseNote {
  let version: String
  let versionLine: Int
  let date: String
  let title: String
  let summary: String
  let type: String
  let breaking: Bool
  let highlights: [String]
  let tags: [String]
  let claudeCode: String
  let codex: String
  let cursor: String?
  let antigravity: String?
  let notesPath: String
}

let knownFields: Set<String> = [
  "version", "date", "title", "summary", "type", "breaking", "highlights", "tags", "testedWith",
]

func isDigits(_ s: Substring) -> Bool {
  !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
}

func isSemver(_ s: String) -> Bool {
  let parts = s.split(separator: ".", omittingEmptySubsequences: false)
  return parts.count == 3 && parts.allSatisfy(isDigits)
}

func isDateShaped(_ s: String) -> Bool {
  let parts = s.split(separator: "-", omittingEmptySubsequences: false)
  guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else {
    return false
  }
  return parts.allSatisfy(isDigits)
}

func isValidCalendarDate(_ s: String) -> Bool {
  guard isDateShaped(s) else { return false }
  let parts = s.split(separator: "-").compactMap { Int($0) }
  guard parts.count == 3 else { return false }
  let year = parts[0]
  let month = parts[1]
  let day = parts[2]
  guard (1...12).contains(month) else { return false }
  let isLeapYear = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  let daysInMonth = [31, isLeapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  return (1...daysInMonth[month - 1]).contains(day)
}

func requireScalar(
  _ frontmatter: Frontmatter, _ key: String, path: String, diagnostics: Diagnostics
) -> (String, Int)? {
  guard let value = frontmatter.values[key] else {
    diagnostics.add(path, 1, "missing field '\(key)'")
    return nil
  }
  let line = frontmatter.lines[key] ?? 1
  guard case .scalar(let token) = value else {
    diagnostics.add(path, line, "field '\(key)' must be a single value")
    return nil
  }
  return (token.value, line)
}

func parseReleaseNote(path: String, name: String, content: String, diagnostics: Diagnostics)
  -> ReleaseNote?
{
  let lines = content.components(separatedBy: "\n").map { Substring($0) }
  guard !lines.isEmpty, lines[0] == "---" else {
    diagnostics.add(path, 1, "missing frontmatter opening '---'")
    return nil
  }
  var closingIndex: Int? = nil
  for idx in 1..<lines.count {
    if lines[idx] == "---" {
      closingIndex = idx
      break
    }
  }
  guard let closing = closingIndex else {
    diagnostics.add(path, lines.count, "missing frontmatter closing '---'")
    return nil
  }

  let frontmatterLines = Array(lines[1..<closing])
  let frontmatter = parseFrontmatter(
    path: path, lines: frontmatterLines, startLine: 2, diagnostics: diagnostics)

  for key in frontmatter.values.keys where !knownFields.contains(key) {
    diagnostics.add(path, frontmatter.lines[key] ?? 1, "unknown field '\(key)'")
  }

  let expectedVersion = name.hasPrefix("release-") && name.hasSuffix(".md")
    ? String(name.dropFirst("release-".count).dropLast(".md".count))
    : ""

  var hadErrors = false

  guard let (version, versionLine) = requireScalar(frontmatter, "version", path: path, diagnostics: diagnostics)
  else {
    hadErrors = true
    return nil
  }
  if !isSemver(version) {
    diagnostics.add(path, versionLine, "version '\(version)' is not semver x.y.z")
    hadErrors = true
  } else if version != expectedVersion {
    diagnostics.add(
      path, versionLine, "version '\(version)' does not match filename '\(name)'")
    hadErrors = true
  }

  guard let (date, dateLine) = requireScalar(frontmatter, "date", path: path, diagnostics: diagnostics)
  else {
    hadErrors = true
    return nil
  }
  if !isValidCalendarDate(date) {
    diagnostics.add(path, dateLine, "date '\(date)' must be a valid YYYY-MM-DD date")
    hadErrors = true
  }

  guard let (title, titleLine) = requireScalar(frontmatter, "title", path: path, diagnostics: diagnostics)
  else {
    hadErrors = true
    return nil
  }
  if title.count > 90 {
    diagnostics.add(path, titleLine, "title is \(title.count) characters, more than 90")
    hadErrors = true
  }

  guard
    let (summary, summaryLine) = requireScalar(
      frontmatter, "summary", path: path, diagnostics: diagnostics)
  else {
    hadErrors = true
    return nil
  }
  if summary.count > 400 {
    diagnostics.add(path, summaryLine, "summary is \(summary.count) characters, more than 400")
    hadErrors = true
  }

  guard let (type, typeLine) = requireScalar(frontmatter, "type", path: path, diagnostics: diagnostics)
  else {
    hadErrors = true
    return nil
  }
  if !["major", "minor", "patch"].contains(type) {
    diagnostics.add(path, typeLine, "type '\(type)' must be one of major, minor, patch")
    hadErrors = true
  }

  var breaking = false
  if let value = frontmatter.values["breaking"] {
    let line = frontmatter.lines["breaking"] ?? 1
    if case .scalar(let token) = value, token.isUnquotedTrue || token.isUnquotedFalse {
      breaking = token.isUnquotedTrue
    } else {
      diagnostics.add(path, line, "field 'breaking' must be true or false")
      hadErrors = true
    }
  } else {
    diagnostics.add(path, 1, "missing field 'breaking'")
    hadErrors = true
  }

  var highlights: [String] = []
  if let value = frontmatter.values["highlights"] {
    let line = frontmatter.lines["highlights"] ?? 1
    if case .list(let items) = value {
      highlights = items.map { $0.value }
      if highlights.isEmpty || highlights.count > 3 {
        diagnostics.add(
          path, line, "field 'highlights' must have between 1 and 3 items")
        hadErrors = true
      }
    } else {
      diagnostics.add(path, line, "field 'highlights' must be a list")
      hadErrors = true
    }
  } else {
    diagnostics.add(path, 1, "missing field 'highlights'")
    hadErrors = true
  }

  var tags: [String] = []
  if let value = frontmatter.values["tags"] {
    let line = frontmatter.lines["tags"] ?? 1
    if case .list(let items) = value {
      tags = items.map { $0.value }
      if tags.count > 5 {
        diagnostics.add(path, line, "field 'tags' must have at most 5 items")
        hadErrors = true
      }
    } else {
      diagnostics.add(path, line, "field 'tags' must be a list")
      hadErrors = true
    }
  } else {
    diagnostics.add(path, 1, "missing field 'tags'")
    hadErrors = true
  }

  var claudeCode = ""
  var codex = ""
  var cursor: String? = nil
  var antigravity: String? = nil
  let testedWithKeys: Set<String> = ["claudeCode", "codex", "cursor", "antigravity"]
  if let value = frontmatter.values["testedWith"] {
    let line = frontmatter.lines["testedWith"] ?? 1
    if case .map(let entries) = value {
      for extraKey in entries.keys where !testedWithKeys.contains(extraKey) {
        diagnostics.add(path, line, "unknown field 'testedWith.\(extraKey)'")
        hadErrors = true
      }
      if let token = entries["claudeCode"] {
        claudeCode = token.value
      } else {
        diagnostics.add(path, line, "field 'testedWith' is missing 'claudeCode'")
        hadErrors = true
      }
      if let token = entries["codex"] {
        codex = token.value
      } else {
        diagnostics.add(path, line, "field 'testedWith' is missing 'codex'")
        hadErrors = true
      }
      if let token = entries["cursor"] {
        cursor = token.value
      }
      if let token = entries["antigravity"] {
        antigravity = token.value
      }
    } else {
      diagnostics.add(path, line, "field 'testedWith' must be a map")
      hadErrors = true
    }
  } else {
    diagnostics.add(path, 1, "missing field 'testedWith'")
    hadErrors = true
  }

  let bodyStartLine = closing + 2
  let bodyLines = closing + 1 < lines.count ? Array(lines[(closing + 1)...]) : []
  if !validateBody(path: path, lines: bodyLines, startLine: bodyStartLine, diagnostics: diagnostics)
  {
    hadErrors = true
  }

  if hadErrors { return nil }

  return ReleaseNote(
    version: version, versionLine: versionLine, date: date, title: title, summary: summary,
    type: type, breaking: breaking, highlights: highlights, tags: tags, claudeCode: claudeCode,
    codex: codex, cursor: cursor, antigravity: antigravity, notesPath: path)
}

struct HeaderOccurrence {
  let title: String
  let line: Int
}

func validateBody(
  path: String, lines: [Substring], startLine: Int, diagnostics: Diagnostics
) -> Bool {
  var headers: [HeaderOccurrence] = []
  var sectionLines: [Int: [Substring]] = [:]
  var currentHeaderIndex: Int? = nil
  var preamble: [Substring] = []

  for (offset, line) in lines.enumerated() {
    if line.hasPrefix("## ") {
      let title = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
      headers.append(HeaderOccurrence(title: title, line: startLine + offset))
      currentHeaderIndex = headers.count - 1
      sectionLines[headers.count - 1] = []
    } else if let idx = currentHeaderIndex {
      sectionLines[idx, default: []].append(line)
    } else {
      preamble.append(line)
    }
  }

  var ok = true

  if preamble.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
    diagnostics.add(path, startLine, "unexpected content before the first '## ' section")
    ok = false
  }

  let required = ["Added", "Changed", "Fixed", "Removed", "Security"]
  for (idx, expected) in required.enumerated() {
    if idx >= headers.count {
      let line = headers.last?.line ?? startLine
      diagnostics.add(path, line, "missing section '## \(expected)'")
      ok = false
      break
    }
    if headers[idx].title != expected {
      diagnostics.add(
        path, headers[idx].line,
        "expected section '## \(expected)' but found '## \(headers[idx].title)'")
      ok = false
      break
    }
    let content = sectionLines[idx] ?? []
    if !content.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
      diagnostics.add(
        path, headers[idx].line,
        "section '## \(expected)' must not be empty; use '- None.'")
      ok = false
    }
  }

  if headers.count > required.count {
    let extra = headers[required.count...].map { $0.title }
    let allowed: [[String]] = [[], ["Upgrading"], ["Notes"], ["Upgrading", "Notes"]]
    if !allowed.contains(where: { $0 == extra }) {
      diagnostics.add(
        path, headers[required.count].line,
        "sections after '## Security' must be only an optional '## Upgrading' then an optional '## Notes'"
      )
      ok = false
    }
  }

  return ok
}

func semverParts(_ v: String) -> [Int] {
  v.split(separator: ".").compactMap { Int($0) }
}

func isNewer(_ a: ReleaseNote, _ b: ReleaseNote) -> Bool {
  semverParts(b.version).lexicographicallyPrecedes(semverParts(a.version))
}

func jsonString(_ s: String) -> String {
  var result = "\""
  for scalar in s.unicodeScalars {
    switch scalar {
    case "\"": result += "\\\""
    case "\\": result += "\\\\"
    case "\n": result += "\\n"
    case "\t": result += "\\t"
    case "\r": result += "\\r"
    default:
      if scalar.value < 0x20 {
        result += String(format: "\\u%04x", scalar.value)
      } else {
        result.unicodeScalars.append(scalar)
      }
    }
  }
  result += "\""
  return result
}

func renderIndex(_ notes: [ReleaseNote]) -> String {
  var lines: [String] = []
  lines.append("{")
  lines.append("  \"schemaVersion\": 1,")
  if notes.isEmpty {
    lines.append("  \"releases\": []")
  } else {
    lines.append("  \"releases\": [")
    for (index, note) in notes.enumerated() {
      lines.append("    {")
      lines.append("      \"version\": \(jsonString(note.version)),")
      lines.append("      \"date\": \(jsonString(note.date)),")
      lines.append("      \"title\": \(jsonString(note.title)),")
      lines.append("      \"summary\": \(jsonString(note.summary)),")
      lines.append("      \"type\": \(jsonString(note.type)),")
      lines.append("      \"breaking\": \(note.breaking ? "true" : "false"),")
      if note.highlights.isEmpty {
        lines.append("      \"highlights\": [],")
      } else {
        lines.append("      \"highlights\": [")
        for (i, h) in note.highlights.enumerated() {
          let comma = i == note.highlights.count - 1 ? "" : ","
          lines.append("        \(jsonString(h))\(comma)")
        }
        lines.append("      ],")
      }
      if note.tags.isEmpty {
        lines.append("      \"tags\": [],")
      } else {
        lines.append("      \"tags\": [")
        for (i, t) in note.tags.enumerated() {
          let comma = i == note.tags.count - 1 ? "" : ","
          lines.append("        \(jsonString(t))\(comma)")
        }
        lines.append("      ],")
      }
      var testedWith = [("claudeCode", note.claudeCode), ("codex", note.codex)]
      if let cursor = note.cursor {
        testedWith.append(("cursor", cursor))
      }
      if let antigravity = note.antigravity {
        testedWith.append(("antigravity", antigravity))
      }
      lines.append("      \"testedWith\": {")
      for (i, (host, version)) in testedWith.enumerated() {
        let comma = i == testedWith.count - 1 ? "" : ","
        lines.append("        \(jsonString(host)): \(jsonString(version))\(comma)")
      }
      lines.append("      },")
      lines.append("      \"notes\": \(jsonString(note.notesPath))")
      let closingComma = index == notes.count - 1 ? "" : ","
      lines.append("    }\(closingComma)")
    }
    lines.append("  ]")
  }
  lines.append("}")
  return lines.joined(separator: "\n") + "\n"
}

func writeStderr(_ s: String) {
  FileHandle.standardError.write(s.data(using: .utf8) ?? Data())
}

func run() -> Int32 {
  var checkOnly = false
  var dir = "releases"
  let args = Array(CommandLine.arguments.dropFirst())
  var i = 0
  while i < args.count {
    switch args[i] {
    case "--check":
      checkOnly = true
    case "--dir":
      i += 1
      guard i < args.count else {
        writeStderr("release-index: --dir requires a value\n")
        return 1
      }
      dir = args[i]
    default:
      writeStderr("release-index: unknown argument '\(args[i])'\n")
      return 1
    }
    i += 1
  }

  let fileManager = FileManager.default
  var isDirectory: ObjCBool = false
  var fileNames: [String] = []
  if fileManager.fileExists(atPath: dir, isDirectory: &isDirectory), isDirectory.boolValue {
    let entries = (try? fileManager.contentsOfDirectory(atPath: dir)) ?? []
    fileNames = entries.filter { $0.hasPrefix("release-") && $0.hasSuffix(".md") }.sorted()
  }

  let diagnostics = Diagnostics()
  var notes: [ReleaseNote] = []
  var seenVersions: [String: String] = [:]

  for name in fileNames {
    let path = (dir as NSString).appendingPathComponent(name)
    guard let data = fileManager.contents(atPath: path),
      let content = String(data: data, encoding: .utf8)
    else {
      diagnostics.add(path, 1, "could not read file as UTF-8")
      continue
    }
    guard
      let note = parseReleaseNote(
        path: path, name: name, content: content, diagnostics: diagnostics)
    else { continue }
    if let existingPath = seenVersions[note.version] {
      diagnostics.add(
        path, note.versionLine,
        "duplicate version '\(note.version)' also used by \(existingPath)")
    } else {
      seenVersions[note.version] = path
      notes.append(note)
    }
  }

  if !diagnostics.isEmpty {
    for diagnostic in diagnostics.items {
      writeStderr("\(diagnostic.file):\(diagnostic.line): \(diagnostic.message)\n")
    }
    return 1
  }

  notes.sort(by: isNewer)
  let rendered = renderIndex(notes)
  let indexPath = (dir as NSString).appendingPathComponent("index.json")

  if checkOnly {
    let existing = (try? String(contentsOfFile: indexPath, encoding: .utf8)) ?? ""
    if existing != rendered {
      writeStderr("\(indexPath):1: index.json is stale; run swift scripts/release-index.swift\n")
      return 1
    }
    print("release-index: ok")
    return 0
  }

  do {
    if !fileManager.fileExists(atPath: dir) {
      try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    try rendered.write(toFile: indexPath, atomically: true, encoding: .utf8)
  } catch {
    writeStderr("\(indexPath):1: could not write index.json: \(error)\n")
    return 1
  }
  print("release-index: ok")
  return 0
}

exit(run())
