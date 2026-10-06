import ApprovalCore
import Darwin
import Foundation

@MainActor
enum WaitingRecorder {
  static let noticeCommand = "notice"

  static func recordTurnEnded(
    input: Data, host: ApprovalCore.Host, settings: Settings, paths: AppPaths, log: EventLog
  ) -> Never {
    guard let envelope = WaitingEnvelope.parse(input, host: host) else {
      log.write("waiting: unparseable input")
      exit(0)
    }
    guard settings.waitingNotices else {
      log.write("waiting: notices off")
      exit(0)
    }
    if host == .claude {
      let registryEntry = SessionRegistry.findEntry(
        sessionID: envelope.sessionID, in: paths.claudeSessionsDirectory)
      if case .skip = HeadlessSessionGate.decide(
        registryEntry: registryEntry, includeHeadlessSessions: false)
      {
        log.write("waiting: skipped non-interactive session")
        exit(0)
      }
    }
    let hostApp = HostApp.resolve()
    let agent = AgentProcess.resolve()
    let record = WaitingRecord(
      host: host, sessionID: envelope.sessionID, projectName: envelope.projectName,
      projectPath: envelope.projectPath,
      transcriptPath: envelope.transcriptPath
        ?? codexRolloutPath(host: host, sessionID: envelope.sessionID),
      reason: .turnEnded, recordedAt: Date(), appBundleID: hostApp?.bundleIdentifier,
      appPID: hostApp?.processIdentifier, appName: hostApp?.localizedName,
      agentPID: agent?.pid, agentStart: agent?.start)
    recordAndNotify(record, paths: paths, log: log)
    exit(0)
  }

  static func clearRecord(input: Data, host: ApprovalCore.Host, paths: AppPaths, log: EventLog) {
    guard let envelope = WaitingEnvelope.parse(input, host: host) else { return }
    let store = WaitingStore(directory: paths.waitingDirectory)
    if store.deleteRecord(host: host, sessionID: envelope.sessionID) {
      log.write("waiting: \(host.rawValue) \(envelope.projectName) working again")
    }
  }

  static func codexRolloutPath(host: ApprovalCore.Host, sessionID: String) -> String? {
    guard host == .codex else { return nil }
    let codexHome =
      ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
      ?? NSHomeDirectory() + "/.codex"
    return CodexRolloutLocator.find(
      sessionID: sessionID,
      sessionsDirectory: URL(fileURLWithPath: codexHome).appendingPathComponent("sessions"))
  }

  static func recordAndNotify(_ record: WaitingRecord, paths: AppPaths, log: EventLog) {
    let recordFile: URL
    do {
      recordFile = try WaitingStore(directory: paths.waitingDirectory).save(record)
    } catch {
      log.write("waiting: failed to record: \(error)")
      return
    }
    guard spawnNotice(recordFile: recordFile) else {
      log.write("waiting: failed to start the notice")
      return
    }
    let suffix = record.reason == .handedBack ? " (handed back)" : ""
    log.write("waiting: recorded \(record.host.rawValue) \(record.projectName)\(suffix)")
  }

  private static func spawnNotice(recordFile: URL) -> Bool {
    guard let executable = Bundle.main.executableURL?.path else { return false }
    var attributes: posix_spawnattr_t?
    guard posix_spawnattr_init(&attributes) == 0 else { return false }
    defer { posix_spawnattr_destroy(&attributes) }
    guard
      posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        == 0
    else { return false }
    var fileActions: posix_spawn_file_actions_t?
    guard posix_spawn_file_actions_init(&fileActions) == 0 else { return false }
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    let nullActions = [
      posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
      posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0),
      posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0),
    ]
    guard nullActions.allSatisfy({ $0 == 0 }) else { return false }
    let arguments = [executable, noticeCommand, recordFile.path]
    var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
    defer {
      for argument in argv {
        free(argument)
      }
    }
    var pid: pid_t = 0
    return posix_spawn(&pid, executable, &fileActions, &attributes, &argv, environ) == 0
  }
}

struct WaitingHandBack {
  let request: ApprovalRequest
  let hostApp: HostApp?
  let isEnabled: Bool
  let paths: AppPaths
  let log: EventLog

  init(
    request: ApprovalRequest, mode: PanelRunMode, settings: Settings, hostApp: HostApp?,
    paths: AppPaths, log: EventLog
  ) {
    self.request = request
    self.hostApp = hostApp
    self.isEnabled = mode == .hook && settings.waitingNotices
    self.paths = paths
    self.log = log
  }

  @MainActor
  private var watchedTranscriptPath: String? {
    guard
      let mainPath = request.transcriptPath
        ?? WaitingRecorder.codexRolloutPath(host: request.host, sessionID: request.sessionID)
    else { return nil }
    guard let agentID = request.agentID else { return mainPath }
    let subagentPath = SubagentChainReader.transcriptPath(
      mainTranscriptPath: mainPath, agentID: agentID)
    return FileManager.default.fileExists(atPath: subagentPath) ? subagentPath : mainPath
  }

  @MainActor
  func record() {
    guard isEnabled else { return }
    let agent = AgentProcess.resolve()
    let record = WaitingRecord(
      host: request.host, sessionID: request.sessionID, projectName: request.projectName,
      projectPath: request.cwd, transcriptPath: watchedTranscriptPath, reason: .handedBack,
      recordedAt: Date(), appBundleID: hostApp?.bundleIdentifier,
      appPID: hostApp?.processIdentifier, appName: hostApp?.localizedName,
      agentPID: agent?.pid, agentStart: agent?.start)
    WaitingRecorder.recordAndNotify(record, paths: paths, log: log)
  }
}

enum AgentProcess {
  static let shellNames: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]

  static func resolve(ancestry: [Int32] = ProcessAncestry.chain(from: getppid()))
    -> (pid: Int32, start: UInt64?)?
  {
    for pid in ancestry {
      guard let name = name(of: pid) else { return nil }
      guard shellNames.contains(name) else {
        return (pid, ProcessLiveness.startTime(of: pid))
      }
    }
    return nil
  }

  private static func name(of pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
    let length = proc_name(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
  }
}
