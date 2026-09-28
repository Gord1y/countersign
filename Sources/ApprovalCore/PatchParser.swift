import Foundation

public enum DiffLineKind: Sendable, Equatable {
  case context
  case added
  case removed
  case collapsed
}

public struct DiffLine: Sendable, Equatable {
  public let kind: DiffLineKind
  public let text: String

  public init(kind: DiffLineKind, text: String) {
    self.kind = kind
    self.text = text
  }
}

public enum PatchOperation: Sendable, Equatable {
  case add
  case update
  case delete
}

public struct PatchFile: Sendable, Equatable {
  public let operation: PatchOperation
  public let path: String
  public let movedTo: String?
  public let lines: [DiffLine]

  public init(operation: PatchOperation, path: String, movedTo: String?, lines: [DiffLine]) {
    self.operation = operation
    self.path = path
    self.movedTo = movedTo
    self.lines = lines
  }
}

public enum PatchParser {
  static let minimumCollapsedLines = 4
  static let neutralSeparator = "…"

  public static func diff(old: String, new: String) -> [DiffLine] {
    let oldLines = TextLine.split(old)
    let newLines = TextLine.split(new)
    let difference = newLines.difference(from: oldLines)

    var removedOffsets: Set<Int> = []
    var insertedOffsets: Set<Int> = []
    for change in difference {
      switch change {
      case .remove(let offset, _, _):
        removedOffsets.insert(offset)
      case .insert(let offset, _, _):
        insertedOffsets.insert(offset)
      }
    }

    var raw: [(kind: DiffLineKind, text: String)] = []
    var i = 0
    var j = 0
    while i < oldLines.count || j < newLines.count {
      if i < oldLines.count, removedOffsets.contains(i) {
        raw.append((.removed, oldLines[i].text))
        i += 1
      } else if j < newLines.count, insertedOffsets.contains(j) {
        raw.append((.added, newLines[j].text))
        j += 1
      } else if i < oldLines.count, j < newLines.count {
        raw.append((.context, oldLines[i].text))
        i += 1
        j += 1
      } else if i < oldLines.count {
        raw.append((.removed, oldLines[i].text))
        i += 1
      } else {
        raw.append((.added, newLines[j].text))
        j += 1
      }
    }

    return collapseContext(raw)
  }

  private static func collapseContext(_ raw: [(kind: DiffLineKind, text: String)]) -> [DiffLine] {
    var result: [DiffLine] = []
    var index = 0
    while index < raw.count {
      let entry = raw[index]
      if entry.kind != .context {
        result.append(DiffLine(kind: entry.kind, text: entry.text))
        index += 1
        continue
      }

      var runEnd = index
      while runEnd < raw.count, raw[runEnd].kind == .context {
        runEnd += 1
      }
      let run = Array(raw[index..<runEnd])
      let hasPrecedingChange = index > 0
      let hasFollowingChange = runEnd < raw.count
      let length = run.count
      let leftKeep = hasPrecedingChange ? min(3, length) : 0
      let rightKeep = hasFollowingChange ? min(3, length) : 0
      let collapsedCount = length - leftKeep - rightKeep

      if collapsedCount < minimumCollapsedLines {
        for line in run {
          result.append(DiffLine(kind: .context, text: line.text))
        }
      } else {
        for k in 0..<leftKeep {
          result.append(DiffLine(kind: .context, text: run[k].text))
        }
        result.append(
          DiffLine(
            kind: .collapsed,
            text: "\(collapsedCount) unchanged line\(collapsedCount == 1 ? "" : "s")"))
        for k in (length - rightKeep)..<length {
          result.append(DiffLine(kind: .context, text: run[k].text))
        }
      }

      index = runEnd
    }
    return result
  }

  public static func files(inApplyPatch text: String) -> [PatchFile] {
    let lines = TextLine.split(text).map(\.text)

    var result: [PatchFile] = []
    var currentOperation: PatchOperation?
    var currentPath: String?
    var currentMovedTo: String?
    var currentLines: [DiffLine] = []

    func flush() {
      guard let operation = currentOperation, let path = currentPath else { return }
      result.append(
        PatchFile(operation: operation, path: path, movedTo: currentMovedTo, lines: currentLines))
      currentOperation = nil
      currentPath = nil
      currentMovedTo = nil
      currentLines = []
    }

    for line in lines {
      if line == "*** Begin Patch" {
        continue
      }
      if line == "*** End Patch" {
        flush()
        continue
      }
      if let path = stripMarker(line, "*** Add File: ") {
        flush()
        currentOperation = .add
        currentPath = path
        continue
      }
      if let path = stripMarker(line, "*** Delete File: ") {
        flush()
        currentOperation = .delete
        currentPath = path
        continue
      }
      if let path = stripMarker(line, "*** Update File: ") {
        flush()
        currentOperation = .update
        currentPath = path
        continue
      }
      if let movedTo = stripMarker(line, "*** Move to: ") {
        currentMovedTo = movedTo
        continue
      }
      guard currentOperation != nil else { continue }
      if line.hasPrefix("@@") {
        let anchor = hunkAnchor(line)
        if !anchor.isEmpty {
          currentLines.append(DiffLine(kind: .collapsed, text: anchor))
        } else if let last = currentLines.last, last.kind != .collapsed {
          currentLines.append(DiffLine(kind: .collapsed, text: neutralSeparator))
        }
        continue
      }
      guard let first = line.first else {
        currentLines.append(DiffLine(kind: .context, text: ""))
        continue
      }
      let content = String(line.dropFirst())
      switch first {
      case " ":
        if content == "*** End of File" { continue }
        currentLines.append(DiffLine(kind: .context, text: content))
      case "-":
        currentLines.append(DiffLine(kind: .removed, text: content))
      case "+":
        currentLines.append(DiffLine(kind: .added, text: content))
      default:
        currentLines.append(DiffLine(kind: .context, text: line))
      }
    }
    flush()

    return result
  }

  private static func stripMarker(_ line: String, _ marker: String) -> String? {
    guard line.hasPrefix(marker) else { return nil }
    return String(line.dropFirst(marker.count))
  }

  static func hunkAnchor(_ header: String) -> String {
    let rest = header.dropFirst(2).trimmingCharacters(in: .whitespaces)
    guard
      let ranges = rest.range(
        of: #"^-\d+(,\d+)? \+\d+(,\d+)? @@"#, options: .regularExpression)
    else {
      return rest
    }
    return rest[ranges.upperBound...].trimmingCharacters(in: .whitespaces)
  }

  public static func preview(of content: String, lineLimit: Int) -> (
    lines: [String], remaining: Int
  ) {
    let allLines = TextLine.split(content).map(\.text)
    let safeLimit = max(0, lineLimit)
    let limited = Array(allLines.prefix(safeLimit))
    let remaining = max(0, allLines.count - limited.count)
    return (limited, remaining)
  }
}
