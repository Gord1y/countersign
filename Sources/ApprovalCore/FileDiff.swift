import Foundation

public enum NumberedLineKind: Sendable, Equatable {
  case context
  case added
  case removed
}

public struct NumberedLine: Sendable, Equatable {
  public let kind: NumberedLineKind
  public let text: String
  public let oldNumber: Int?
  public let newNumber: Int?

  public init(kind: NumberedLineKind, text: String, oldNumber: Int?, newNumber: Int?) {
    self.kind = kind
    self.text = text
    self.oldNumber = oldNumber
    self.newNumber = newNumber
  }
}

public enum DiffSegment: Sendable, Equatable {
  case visible([NumberedLine])
  case gap([NumberedLine])
}

public enum FileDiffStatus: Sendable, Equatable {
  case modified
  case created
  case deleted
  case moved(to: String)
}

public struct FileDiff: Sendable, Equatable {
  public let path: String
  public let displayPath: String
  public let status: FileDiffStatus
  public let segments: [DiffSegment]

  public init(path: String, displayPath: String, status: FileDiffStatus, segments: [DiffSegment]) {
    self.path = path
    self.displayPath = displayPath
    self.status = status
    self.segments = segments
  }
}

public enum FileDiffBuilder {
  static let maxGuardedBytes = 2 * 1024 * 1024
  static let maxGuardedLines = 20_000
  static let createdVisibleLineCount = 40

  public static func edit(
    path: String, fileContent: String, oldString: String, newString: String, replaceAll: Bool
  ) -> FileDiff? {
    guard !exceedsGuardLimits(fileContent) else { return nil }
    guard
      let newContent = replacing(
        oldString, with: newString, in: fileContent, replaceAll: replaceAll)
    else {
      return nil
    }
    let numbered = numberedDiff(old: fileContent, new: newContent)
    return FileDiff(
      path: path, displayPath: path, status: .modified, segments: segments(for: numbered))
  }

  public static func write(path: String, fileContent: String?, newContent: String) -> FileDiff {
    guard let fileContent, !exceedsGuardLimits(fileContent) else {
      return createdDiff(path: path, content: newContent)
    }
    let numbered = numberedDiff(old: fileContent, new: newContent)
    return FileDiff(
      path: path, displayPath: path, status: .modified, segments: segments(for: numbered))
  }

  public static func patch(_ file: PatchFile, fileContent: String?) -> FileDiff? {
    switch file.operation {
    case .add:
      return createdDiff(path: file.path, content: addedContent(from: file.lines))
    case .delete:
      guard let fileContent, !exceedsGuardLimits(fileContent) else { return nil }
      return deletedDiff(path: file.path, content: fileContent)
    case .update:
      guard let fileContent, !exceedsGuardLimits(fileContent) else { return nil }
      guard let newContent = applyingHunks(file.lines, to: fileContent) else { return nil }
      let numbered = numberedDiff(old: fileContent, new: newContent)
      var status: FileDiffStatus = .modified
      if let movedTo = file.movedTo, movedTo != file.path {
        status = .moved(to: movedTo)
      }
      return FileDiff(
        path: file.path, displayPath: file.path, status: status, segments: segments(for: numbered))
    }
  }

  public static func load(for request: ApprovalRequest) -> [FileDiff]? {
    guard case .permission(let prompt) = request.kind else { return nil }
    switch prompt.body {
    case .edit(let path, let oldString, let newString, let replaceAll):
      guard let content = readFile(at: path) else { return nil }
      guard
        let diff = edit(
          path: path, fileContent: content, oldString: oldString, newString: newString,
          replaceAll: replaceAll)
      else {
        return nil
      }
      return [withDisplayPath(diff, cwd: request.cwd)]
    case .write(let path, let content):
      let existing = readFile(at: path)
      let diff = write(path: path, fileContent: existing, newContent: content)
      return [withDisplayPath(diff, cwd: request.cwd)]
    case .patch(let text):
      let files = PatchParser.files(inApplyPatch: text)
      guard !files.isEmpty else { return nil }
      var results: [FileDiff] = []
      for file in files {
        let absolutePath = resolvePath(file.path, cwd: request.cwd)
        let content: String?
        switch file.operation {
        case .add:
          content = nil
        case .update, .delete:
          content = readFile(at: absolutePath)
        }
        let resolvedFile = PatchFile(
          operation: file.operation,
          path: absolutePath,
          movedTo: file.movedTo.map { resolvePath($0, cwd: request.cwd) },
          lines: file.lines)
        guard let diff = patch(resolvedFile, fileContent: content) else { return nil }
        results.append(withDisplayPath(diff, cwd: request.cwd))
      }
      return results
    default:
      return nil
    }
  }

  static func exceedsGuardLimits(_ content: String) -> Bool {
    if content.utf8.count > maxGuardedBytes { return true }
    if TextLine.split(content).count > maxGuardedLines { return true }
    return false
  }

  static func replacing(
    _ oldString: String, with newString: String, in content: String, replaceAll: Bool
  )
    -> String?
  {
    guard let firstRange = content.range(of: oldString) else { return nil }
    if replaceAll {
      return content.replacingOccurrences(of: oldString, with: newString)
    }
    var result = content
    result.replaceSubrange(firstRange, with: newString)
    return result
  }

  public static func gapTitle(hiddenCount: Int, of lines: [NumberedLine]) -> String {
    let adjective = lines.allSatisfy { $0.kind == .context } ? "unchanged" : "more"
    return "Show \(hiddenCount) \(adjective) line\(hiddenCount == 1 ? "" : "s")"
  }

  static func addedContent(from lines: [DiffLine]) -> String {
    lines.filter { $0.kind != .collapsed }.map(\.text).joined(separator: "\n")
  }

  static func createdDiff(path: String, content: String) -> FileDiff {
    let numbered = TextLine.split(content).enumerated().map { index, line in
      NumberedLine(kind: .added, text: line.text, oldNumber: nil, newNumber: index + 1)
    }
    return FileDiff(
      path: path, displayPath: path, status: .created,
      segments: cappedSegments(numbered, visibleCount: createdVisibleLineCount))
  }

  static func deletedDiff(path: String, content: String) -> FileDiff {
    let numbered = TextLine.split(content).enumerated().map { index, line in
      NumberedLine(kind: .removed, text: line.text, oldNumber: index + 1, newNumber: nil)
    }
    return FileDiff(
      path: path, displayPath: path, status: .deleted,
      segments: cappedSegments(numbered, visibleCount: createdVisibleLineCount))
  }

  static func cappedSegments(_ lines: [NumberedLine], visibleCount: Int) -> [DiffSegment] {
    let cap = min(visibleCount, lines.count)
    var result: [DiffSegment] = []
    if cap > 0 {
      result.append(.visible(Array(lines.prefix(cap))))
    }
    if lines.count > cap {
      result.append(.gap(Array(lines.suffix(from: cap))))
    }
    return result
  }

  static func readFile(at path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func resolvePath(_ path: String, cwd: String) -> String {
    guard !path.hasPrefix("/") else { return path }
    let cwdPrefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
    return cwdPrefix + path
  }

  static func withDisplayPath(_ diff: FileDiff, cwd: String) -> FileDiff {
    FileDiff(
      path: diff.path, displayPath: computeDisplayPath(diff.path, cwd: cwd), status: diff.status,
      segments: diff.segments)
  }

  static func computeDisplayPath(_ path: String, cwd: String) -> String {
    if path == cwd {
      return "."
    }
    let cwdPrefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
    if path.hasPrefix(cwdPrefix) {
      return String(path.dropFirst(cwdPrefix.count))
    }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home {
      return "~"
    }
    let homePrefix = home.hasSuffix("/") ? home : home + "/"
    if path.hasPrefix(homePrefix) {
      return "~/" + path.dropFirst(homePrefix.count)
    }
    return path
  }
}
