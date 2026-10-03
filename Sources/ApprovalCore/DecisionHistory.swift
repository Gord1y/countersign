import Foundation

public enum DecisionAnswer: String, Codable, Sendable, Equatable, CaseIterable {
  case approved
  case denied
  case allowedByRule
  case deniedByRule
  case answeredInChat
  case resolvedElsewhere
  case continued
  case compactAfterStep
  case handOff
  case notThisSession
  case dismissed

  public static func answer(
    for outcome: ApprovalOutcome, checkpointChoice: ContextCheckpointChoice?,
    isCheckpoint: Bool
  ) -> DecisionAnswer {
    if isCheckpoint {
      guard let checkpointChoice else { return .dismissed }
      switch checkpointChoice {
      case .continueWorking: return .continued
      case .compactAfterStep: return .compactAfterStep
      case .handOff: return .handOff
      case .notThisSession: return .notThisSession
      }
    }
    switch outcome {
    case .allow: return .approved
    case .deny: return .denied
    case .noDecision, .addContext: return .answeredInChat
    }
  }
}

public struct DecisionHistoryEntry: Codable, Sendable, Equatable {
  public var date: Date
  public var host: Host
  public var project: String
  public var tool: String
  public var title: String
  public var answer: DecisionAnswer

  public init(
    date: Date, host: Host, project: String, tool: String, title: String, answer: DecisionAnswer
  ) {
    self.date = date
    self.host = host
    self.project = project
    self.tool = tool
    self.title = title
    self.answer = answer
  }

  public init(request: ApprovalRequest, answer: DecisionAnswer, date: Date = Date()) {
    self.init(
      date: date, host: request.host, project: request.projectName, tool: request.toolName,
      title: DecisionTitle.title(for: request), answer: answer)
  }
}

public enum DecisionTitle {
  public static let maxLength = 80

  public static func title(for request: ApprovalRequest) -> String {
    cut(rawTitle(for: request))
  }

  static func cut(_ text: String) -> String {
    guard text.count > maxLength else { return text }
    return String(text.prefix(maxLength - 1)) + "…"
  }

  private static func rawTitle(for request: ApprovalRequest) -> String {
    switch request.kind {
    case .plan:
      return "Plan"
    case .contextCheckpoint(let prompt):
      return "Context at \(ContextCheckpointNotes.tokenText(prompt.tokens))"
    case .questions(let questions):
      return nonEmpty(questions.first?.header) ?? nonEmpty(questions.first?.question)
        ?? request.toolName
    case .permission(let prompt):
      return permissionTitle(prompt.body, request: request)
    }
  }

  private static func permissionTitle(_ body: ToolBody, request: ApprovalRequest) -> String {
    switch body {
    case .bash(let command, _):
      return nonEmpty(firstLine(of: command)) ?? request.toolName
    case .edit(let path, _, _, _), .write(let path, _):
      return nonEmpty(fileName(of: path)) ?? request.toolName
    case .mcp(_, let tool, _):
      return nonEmpty(tool) ?? request.toolName
    case .json(let value):
      if ["Edit", "Write", "MultiEdit"].contains(request.toolName),
        let path = value["file_path"]?.stringValue, let name = nonEmpty(fileName(of: path))
      {
        return name
      }
      return request.toolName
    case .patch, .webFetch:
      return request.toolName
    }
  }

  private static func firstLine(of text: String) -> String {
    let line = text.split(
      maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: \.isNewline
    ).first
    return String(line ?? "").trimmingCharacters(in: .whitespaces)
  }

  private static func fileName(of path: String) -> String {
    (path as NSString).lastPathComponent
  }

  private static func nonEmpty(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
    else { return nil }
    return trimmed
  }
}

public struct DecisionHistory: Sendable {
  public static let keptEntries = 200
  public static let trimThreshold = 250

  let file: URL
  let lockFile: URL

  public init(file: URL, lockFile: URL) {
    self.file = file
    self.lockFile = lockFile
  }

  public init(paths: AppPaths) {
    self.init(file: paths.decisionHistoryFile, lockFile: paths.decisionHistoryLockFile)
  }

  public func append(_ entry: DecisionHistoryEntry) throws {
    try withLock {
      var lines = readLines()
      lines.append(try Self.encode(entry))
      if lines.count > Self.trimThreshold {
        lines = Array(lines.suffix(Self.keptEntries))
      }
      try write(lines)
    }
  }

  public func recent(limit: Int) -> [DecisionHistoryEntry] {
    guard limit > 0 else { return [] }
    let decoder = Self.decoder()
    let entries = readLines().compactMap { line in
      try? decoder.decode(DecisionHistoryEntry.self, from: Data(line.utf8))
    }
    return Array(entries.suffix(limit).reversed())
  }

  public func clear() throws {
    try withLock {
      try write([])
    }
  }

  private func withLock<Result>(_ body: () throws -> Result) throws -> Result {
    var attempts = 0
    while true {
      if let lock = try ExclusiveFileLock.acquire(lockFile) {
        defer { lock.release() }
        return try body()
      }
      attempts += 1
      guard attempts < 100 else { throw DecisionHistoryError.lockBusy }
      Thread.sleep(forTimeInterval: 0.02)
    }
  }

  private func readLines() -> [String] {
    guard let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8)
    else { return [] }
    return text.split(whereSeparator: \.isNewline).map(String.init)
  }

  private func write(_ lines: [String]) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    try Data(text.utf8).write(to: file, options: .atomic)
  }

  private static func encode(_ entry: DecisionHistoryEntry) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(entry), as: UTF8.self)
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

public enum DecisionHistoryError: Error, Equatable {
  case lockBusy
}
