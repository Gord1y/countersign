import ApprovalCore
import Foundation

@MainActor
enum ContextCheckpointRunner {
  static let stateRetention: TimeInterval = 30 * 24 * 60 * 60

  static func run(
    input: Data, settings: Settings, paths: AppPaths, log: EventLog,
    startedAt: ContinuousClock.Instant
  ) -> Never {
    let checkpointInput: ContextCheckpointInput
    do {
      checkpointInput = try ClaudeAdapter.parseUserPromptSubmit(input)
    } catch {
      log.write("context: unparseable input")
      exit(0)
    }

    let checkpointSettings = settings.contextCheckpoints
    guard checkpointSettings.enabled else {
      log.write("context: off")
      exit(0)
    }

    let registryEntry = SessionRegistry.findEntry(
      sessionID: checkpointInput.sessionID, in: paths.claudeSessionsDirectory)
    if case .skip(let kind) = HeadlessSessionGate.decide(
      registryEntry: registryEntry, includeHeadlessSessions: settings.includeHeadlessSessions)
    {
      log.write("context: skipped, non-interactive session (kind=\(kind))")
      exit(0)
    }

    let sessionID = checkpointInput.sessionID
    guard ContextCheckpointStore.isValidSessionID(sessionID) else {
      log.write("context: unusable session id")
      exit(0)
    }
    let store = ContextCheckpointStore(directory: paths.contextCheckpointsDirectory)
    guard let transcriptPath = checkpointInput.transcriptPath,
      let (reading, modelIdentity) = ContextUsageReader.read(
        transcriptURL: URL(fileURLWithPath: transcriptPath),
        identity: store.load(sessionID: sessionID)?.modelIdentity)
    else {
      log.write("context: no reading")
      exit(0)
    }
    let now = Date()
    store.prune(olderThan: stateRetention, now: now)
    let lockedPlan: ContextCheckpointPlan?
    do {
      lockedPlan = try store.withLock(sessionID: sessionID) {
        let previous = store.load(sessionID: sessionID) ?? .fresh(now: now)
        var plan = ContextCheckpointPlanner.plan(
          reading: reading, previous: previous, settings: checkpointSettings,
          transcriptPath: transcriptPath,
          project: ApprovalRequest.projectName(cwd: checkpointInput.cwd), now: now)
        plan.state.modelIdentity = modelIdentity
        if case .panel = plan.decision {
          plan.state.pendingProcessID = getpid()
        }
        try store.save(plan.state, sessionID: sessionID)
        return plan
      }
    } catch {
      log.write("context: state not saved: \(error)")
      exit(0)
    }
    guard let plan = lockedPlan else {
      log.write("context: state busy")
      exit(0)
    }

    let firedLevelName = firedLevel(in: plan).map(logName(of:))
    if let firedLevelName {
      log.write("context: \(reading.tokens) tokens, \(firedLevelName) fired")
    } else {
      log.write("context: \(reading.tokens) tokens")
    }

    switch plan.decision {
    case .nothing:
      exit(0)
    case .inject(let text):
      HookRunner.writeReply(.addContext(text), host: .claude)
      log.write("outcome: context note (silent, \(firedLevelName ?? "unknown"))")
      exit(0)
    case .panel(let prompt):
      let session = ContextCheckpointSession(
        sessionID: sessionID, store: store,
        watcher: ContextCheckpointWatcher(
          transcriptURL: URL(fileURLWithPath: transcriptPath), sessionID: sessionID,
          processID: getpid(), store: store, baselineCompactionID: reading.compactionID),
        sessionsDirectory: paths.claudeSessionsDirectory, log: log)
      HookRunner.showPanel(
        for: .contextCheckpoint(checkpointInput, prompt: prompt), mode: .checkpoint,
        settings: settings, paths: paths, log: log, startedAt: startedAt, hostApp: nil,
        checkpoint: session)
    }
  }

  private static func firedLevel(in plan: ContextCheckpointPlan) -> ContextLevel? {
    switch plan.decision {
    case .nothing: return nil
    case .inject: return plan.state.fired.max()
    case .panel(let prompt): return prompt.level
    }
  }

  private static func logName(of level: ContextLevel) -> String {
    switch level {
    case .soft: return "soft"
    case .status: return "status"
    case .insist: return "insist"
    }
  }
}

@MainActor
final class ContextCheckpointSession {
  private let sessionID: String
  private let store: ContextCheckpointStore
  private let watcher: ContextCheckpointWatcher
  private let sessionsDirectory: URL
  private let log: EventLog

  init(
    sessionID: String, store: ContextCheckpointStore, watcher: ContextCheckpointWatcher,
    sessionsDirectory: URL, log: EventLog
  ) {
    self.sessionID = sessionID
    self.store = store
    self.watcher = watcher
    self.sessionsDirectory = sessionsDirectory
    self.log = log
  }

  func abandonReason() -> String? {
    watcher.poll()?.rawValue
  }

  func isIdle() -> Bool {
    SessionRegistry.findEntry(sessionID: sessionID, in: sessionsDirectory)?.fields["status"]?
      .stringValue == "idle"
  }

  func mute() {
    do {
      let saved: Void? = try store.withLock(sessionID: sessionID) {
        var state = store.load(sessionID: sessionID) ?? .fresh(now: Date())
        state.muted = true
        try store.save(state, sessionID: sessionID)
      }
      if saved == nil {
        log.write("context: mute not saved: state busy")
      }
    } catch {
      log.write("context: mute not saved: \(error)")
    }
  }
}
