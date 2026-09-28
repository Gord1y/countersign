public enum DoctorStatus: String, Sendable, Equatable {
  case ok
  case warn
  case fail
  case info
}

public struct DoctorLine: Sendable, Equatable {
  public let status: DoctorStatus
  public let check: String
  public let detail: String

  public init(status: DoctorStatus, check: String, detail: String) {
    self.status = status
    self.check = check
    self.detail = detail
  }

  public var text: String {
    "\(status.rawValue) \(check): \(detail)"
  }
}

public enum Doctor {
  public enum FileState: Sendable, Equatable {
    case missing
    case unreadable(String)
    case bytes([UInt8])
  }

  public struct HostInput: Sendable, Equatable {
    public var host: Host
    public var directoryPath: String
    public var filePath: String
    public var directoryExists: Bool
    public var fileState: FileState
    public var executableChecks: [String: Bool]

    public init(
      host: Host, directoryPath: String, filePath: String, directoryExists: Bool,
      fileState: FileState, executableChecks: [String: Bool]
    ) {
      self.host = host
      self.directoryPath = directoryPath
      self.filePath = filePath
      self.directoryExists = directoryExists
      self.fileState = fileState
      self.executableChecks = executableChecks
    }
  }

  public struct Input: Sendable, Equatable {
    public var version: String
    public var resolvedExecutablePath: String
    public var stableExecutablePath: String
    public var hosts: [HostInput]
    public var configPath: String
    public var configFileExists: Bool
    public var configLogLines: [String]
    public var queueDirectoryPath: String
    public var liveTicketCount: Int
    public var pauseState: PauseState
    public var quietUntilDescription: String?
    public var logFilePath: String
    public var logFileSize: Int?
    public var duplicateInstall: DuplicateInstall?
    public var installVersionMismatch: InstallVersionMismatch?
    public var codexHookTrustRecord: CodexHookTrustRecord?
    public var codexConfigFile: FileState

    public init(
      version: String, resolvedExecutablePath: String, stableExecutablePath: String,
      hosts: [HostInput], configPath: String, configFileExists: Bool, configLogLines: [String],
      queueDirectoryPath: String, liveTicketCount: Int, pauseState: PauseState,
      quietUntilDescription: String?, logFilePath: String, logFileSize: Int?,
      codexHookTrustRecord: CodexHookTrustRecord? = nil, codexConfigFile: FileState = .missing
    ) {
      self.version = version
      self.resolvedExecutablePath = resolvedExecutablePath
      self.stableExecutablePath = stableExecutablePath
      self.hosts = hosts
      self.configPath = configPath
      self.configFileExists = configFileExists
      self.configLogLines = configLogLines
      self.queueDirectoryPath = queueDirectoryPath
      self.liveTicketCount = liveTicketCount
      self.pauseState = pauseState
      self.quietUntilDescription = quietUntilDescription
      self.logFilePath = logFilePath
      self.logFileSize = logFileSize
      self.codexHookTrustRecord = codexHookTrustRecord
      self.codexConfigFile = codexConfigFile
    }
  }

  private struct HookEntry: Sendable, Equatable {
    let words: [String]
    let timeoutSeconds: Double?
    let event: String?

    var executablePath: String { words.first ?? "" }
  }

  private enum HookScan: Sendable, Equatable {
    case invalid(String)
    case misshapen
    case entries([HookEntry], missingEvents: [String])
  }

  static let minimumTimeoutSeconds: Double = 600
  static let antigravityStrictness =
    "Antigravity ignores the whole file when any part of it is invalid"

  public static func executablePaths(inHookConfig fileBytes: [UInt8], host: Host) -> [String] {
    guard case .entries(let entries, _) = scanHooks(fileBytes, host: host) else { return [] }
    return entries.map(\.executablePath)
  }

  public static func report(_ input: Input) -> [DoctorLine] {
    var lines: [DoctorLine] = []
    lines.append(
      DoctorLine(
        status: .info, check: "version",
        detail:
          "countersign \(input.version), running at \(input.resolvedExecutablePath), setup would write \(input.stableExecutablePath)"
      ))
    if let duplicateInstall = input.duplicateInstall {
      lines.append(duplicateInstall.doctorLine)
    }
    if let installVersionMismatch = input.installVersionMismatch {
      lines.append(installVersionMismatch.doctorLine)
    }
    for hostInput in input.hosts {
      lines.append(contentsOf: hostLines(hostInput, stablePath: input.stableExecutablePath))
      lines.append(contentsOf: followUpLines(hostInput, input: input))
    }
    lines.append(contentsOf: configLines(input))
    lines.append(
      DoctorLine(
        status: .info, check: "queue",
        detail: "\(input.queueDirectoryPath): \(input.liveTicketCount) live ticket(s)"))
    lines.append(
      DoctorLine(
        status: .info, check: "state",
        detail:
          "\(input.pauseState.description), "
          + (input.quietUntilDescription.map { "quiet until \($0)" } ?? "quiet off")))
    if let size = input.logFileSize {
      lines.append(
        DoctorLine(status: .info, check: "log", detail: "\(input.logFilePath): \(size) byte(s)"))
    } else {
      lines.append(
        DoctorLine(status: .info, check: "log", detail: "\(input.logFilePath): not created yet"))
    }
    return lines
  }

  public static func exitCode(for lines: [DoctorLine]) -> Int32 {
    lines.contains { $0.status == .fail } ? 1 : 0
  }

  private static func hostLines(_ hostInput: HostInput, stablePath: String) -> [DoctorLine] {
    let check = hostInput.host.rawValue
    guard hostInput.directoryExists else {
      return [
        DoctorLine(
          status: .info, check: check, detail: "not installed (\(hostInput.directoryPath))")
      ]
    }
    switch hostInput.fileState {
    case .missing:
      return [
        DoctorLine(
          status: .warn, check: check,
          detail: "\(hostInput.filePath) is missing, run countersign setup")
      ]
    case .unreadable(let reason):
      return [
        DoctorLine(
          status: .fail, check: check,
          detail: "\(hostInput.filePath) could not be read: \(reason)")
      ]
    case .bytes(let bytes):
      if HookSetup.isBlank(bytes) {
        return [
          DoctorLine(
            status: .warn, check: check,
            detail: "\(hostInput.filePath) is empty, run countersign setup")
        ]
      }
      switch scanHooks(bytes, host: hostInput.host) {
      case .invalid(let reason):
        let strictness = hostInput.host == .antigravity ? "; \(antigravityStrictness)" : ""
        return [
          DoctorLine(
            status: .fail, check: check,
            detail: "\(hostInput.filePath) is not valid JSON: \(reason)\(strictness)")
        ]
      case .misshapen:
        return [
          DoctorLine(
            status: .warn, check: check,
            detail:
              "the \(AntigravityHookSetup.hookName) hook in \(hostInput.filePath) is not in the shape setup writes, run countersign setup; \(antigravityStrictness)"
          )
        ]
      case .entries(let entries, let missingEvents):
        guard !entries.isEmpty else {
          return [
            DoctorLine(
              status: .warn, check: check,
              detail: "no countersign entry in \(hostInput.filePath), run countersign setup")
          ]
        }
        let missingLines = missingEvents.map { event in
          DoctorLine(
            status: .warn, check: check,
            detail:
              "no countersign entry under hooks.\(event) in \(hostInput.filePath), run countersign setup"
          )
        }
        return missingLines + entryLines(entries, hostInput: hostInput, stablePath: stablePath)
      }
    }
  }

  private static func followUpLines(_ hostInput: HostInput, input: Input) -> [DoctorLine] {
    let check = hostInput.host.rawValue
    let wiring = HostWiring.status(
      host: hostInput.host, directoryExists: hostInput.directoryExists, file: hostInput.fileState,
      stablePath: input.stableExecutablePath)
    guard wiring == .wired else { return [] }
    switch hostInput.host {
    case .claude:
      return []
    case .codex:
      let verdict = CodexTrustVerdict.judge(
        record: input.codexHookTrustRecord, current: codexCurrentEntry(hostInput),
        table: CodexTrustTable.read(input.codexConfigFile))
      return [codexTrustLine(verdict.state)]
    case .cursor:
      return [DoctorLine(status: .info, check: check, detail: AgentFollowUps.cursorGoodToKnow)]
    case .antigravity:
      return [DoctorLine(status: .info, check: check, detail: AgentFollowUps.antigravityGoodToKnow)]
    }
  }

  private static func codexTrustLine(_ state: CodexHookTrustState) -> DoctorLine {
    let check = Host.codex.rawValue
    let nextStep = AgentFollowUps.codexNextStep
    switch state {
    case .trusted:
      return DoctorLine(status: .ok, check: check, detail: "Codex trusts Countersign's hook")
    case .markedDone:
      return DoctorLine(
        status: .ok, check: check, detail: "you marked Countersign's hook as trusted in Codex")
    case .pending(let reason?, _):
      return DoctorLine(status: .warn, check: check, detail: "\(reason) \(nextStep)")
    case .pending(nil, false):
      return DoctorLine(
        status: .warn, check: check,
        detail: "Codex has not trusted Countersign's hook yet. \(nextStep)")
    case .pending(nil, true), .unknown:
      return DoctorLine(
        status: .info, check: check,
        detail: "cannot tell whether Codex trusts Countersign's hook. \(nextStep)")
    }
  }

  private static func codexCurrentEntry(_ hostInput: HostInput) -> CodexHookTrustCurrent? {
    guard case .bytes(let bytes) = hostInput.fileState else { return nil }
    return CodexHookTrust.current(hooksFileBytes: bytes, hooksFilePath: hostInput.filePath)
  }

  private static func entryLines(
    _ entries: [HookEntry], hostInput: HostInput, stablePath: String
  ) -> [DoctorLine] {
    let check = hostInput.host.rawValue
    var lines: [DoctorLine] = []
    for (offset, entry) in entries.enumerated() {
      let label = label(for: entry, at: offset, in: entries)
      var issues: [DoctorLine] = []
      if entry.executablePath != stablePath {
        issues.append(
          DoctorLine(
            status: .warn, check: check,
            detail:
              "\(label): \(entry.executablePath) differs from the stable path \(stablePath), run countersign setup"
          ))
      }
      if !(hostInput.executableChecks[entry.executablePath] ?? false) {
        issues.append(
          DoctorLine(
            status: .fail, check: check,
            detail: "\(label): \(entry.executablePath) does not exist or is not executable"))
      }
      let timeoutIsLongEnough = entry.timeoutSeconds.map { $0 >= minimumTimeoutSeconds } ?? false
      if !timeoutIsLongEnough {
        let shown = entry.timeoutSeconds.map { "\(formatNumber($0))s" } ?? "not set"
        issues.append(
          DoctorLine(
            status: .warn, check: check,
            detail:
              "\(label): timeout is \(shown), below 600s; a short hook timeout can kill the wait for a person"
          ))
      }
      let arguments = Array(entry.words.dropFirst())
      let expected = HookCommand.arguments(for: hostInput.host)
      if arguments != expected {
        issues.append(
          DoctorLine(
            status: .warn, check: check,
            detail:
              "\(label): arguments \(arguments.joined(separator: " ")) differ from \(expected.joined(separator: " ")), run countersign setup"
          ))
      }
      if issues.isEmpty {
        let timeoutText = entry.timeoutSeconds.map(formatNumber) ?? "not set"
        lines.append(
          DoctorLine(
            status: .ok, check: check,
            detail: "\(label): \(entry.executablePath), timeout \(timeoutText)s"))
      } else {
        lines.append(contentsOf: issues)
      }
    }
    return lines
  }

  private static func label(for entry: HookEntry, at offset: Int, in entries: [HookEntry])
    -> String
  {
    let base = entry.event.map { "\($0) entry" } ?? "entry"
    guard entries.filter({ $0.event == entry.event }).count > 1 else { return base }
    let position = entries[..<offset].filter { $0.event == entry.event }.count + 1
    return "\(base) \(position)"
  }

  private static func configLines(_ input: Input) -> [DoctorLine] {
    guard input.configFileExists else {
      return [
        DoctorLine(
          status: .info, check: "config",
          detail: "\(input.configPath): no config file, using defaults")
      ]
    }
    guard !input.configLogLines.isEmpty else {
      return [
        DoctorLine(status: .ok, check: "config", detail: "\(input.configPath): parsed cleanly")
      ]
    }
    return input.configLogLines.map { DoctorLine(status: .warn, check: "config", detail: $0) }
  }

  private static func scanHooks(_ bytes: [UInt8], host: Host) -> HookScan {
    let root: JSONSpanNode
    do {
      root = try JSONSpanReader.parse(bytes)
    } catch let error as JSONSpanError {
      return .invalid(error.description)
    } catch {
      return .invalid("\(error)")
    }
    switch host {
    case .claude, .codex:
      let entries = HookSetup.sites(in: root).map { entry(for: $0.hook, event: nil) }
      return .entries(entries, missingEvents: [])
    case .cursor:
      let entries = CursorHookSetup.sites(in: root).map { entry(for: $0.hook, event: $0.eventName) }
      return .entries(entries, missingEvents: CursorHookSetup.missingEvents(in: root))
    case .antigravity:
      let entries = AntigravityHookSetup.hookNodes(in: root).map { entry(for: $0, event: nil) }
      if entries.isEmpty, AntigravityHookSetup.hasNamedHook(in: root) {
        return .misshapen
      }
      return .entries(entries, missingEvents: [])
    }
  }

  private static func entry(for hook: JSONSpanNode, event: String?) -> HookEntry {
    let commandString = hook.member(named: "command")?.value.stringValue ?? ""
    let words = HookCommand.words(in: Array(commandString.unicodeScalars), limit: 64).map(\.value)
    let timeout = hook.member(named: "timeout")?.value.numberValue
    return HookEntry(words: words, timeoutSeconds: timeout, event: event)
  }

  private static func formatNumber(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
  }
}
