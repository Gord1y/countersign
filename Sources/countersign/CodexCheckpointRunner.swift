import ApprovalCore
import Foundation

@MainActor
enum CodexCheckpointRunner {
  static func run(
    input: Data, eventName: String, settings: Settings, paths: AppPaths, log: EventLog
  ) -> Never {
    if eventName == ContextHookSetup.toolEventName {
      runAfterToolCall(input: input, settings: settings, paths: paths, log: log)
    }
    runOnPrompt(input: input, settings: settings, paths: paths, log: log)
  }

  private static func runOnPrompt(
    input: Data, settings: Settings, paths: AppPaths, log: EventLog
  ) -> Never {
    let checkpointInput: ContextCheckpointInput
    do {
      checkpointInput = try CodexAdapter.parseContextInput(
        input, eventName: ContextHookSetup.eventName)
    } catch {
      log.write("context: codex unparseable input")
      exit(0)
    }
    guard checkpointInput.agentID == nil else {
      log.write("context: codex subagent prompt, skipped")
      exit(0)
    }
    guard settings.contextCheckpoints.enabled else {
      log.write("context: codex off")
      exit(0)
    }
    let sessionID = checkpointInput.sessionID
    guard ContextCheckpointStore.isValidSessionID(sessionID) else {
      log.write("context: codex unusable session id")
      exit(0)
    }
    guard let transcriptPath = checkpointInput.transcriptPath,
      let codexReading = CodexUsageReader.read(rolloutURL: URL(fileURLWithPath: transcriptPath))
    else {
      log.write("context: codex no reading")
      exit(0)
    }
    let store = ContextCheckpointStore(directory: paths.contextCheckpointsDirectory)
    let now = Date()
    store.prune(olderThan: ContextCheckpointRunner.stateRetention, now: now)
    guard
      let plan = plan(
        codexReading: codexReading, checkpointInput: checkpointInput,
        transcriptPath: transcriptPath, store: store, settings: settings, now: now,
        levels: ContextLevel.allCases, log: log)
    else {
      log.write("context: codex state busy")
      exit(0)
    }

    let firedLevelName = ContextCheckpointRunner.firedLevel(in: plan).map(
      ContextCheckpointRunner.logName(of:))
    if let firedLevelName {
      log.write("context: codex \(codexReading.tokens) tokens, \(firedLevelName) fired")
    } else {
      log.write("context: codex \(codexReading.tokens) tokens")
    }
    guard case .inject(let text) = plan.decision else { exit(0) }
    if let data = CodexAdapter.encodeContext(text, eventName: ContextHookSetup.eventName) {
      ReplyWriter.write(data, to: .standardOutput)
    }
    log.write("outcome: context note (codex, \(firedLevelName ?? "unknown"))")
    exit(0)
  }

  private static func runAfterToolCall(
    input: Data, settings: Settings, paths: AppPaths, log: EventLog
  ) -> Never {
    if PauseSwitch(file: paths.pauseFile).isPaused {
      exit(0)
    }
    let checkpointInput: ContextCheckpointInput
    do {
      checkpointInput = try CodexAdapter.parseContextInput(
        input, eventName: ContextHookSetup.toolEventName)
    } catch {
      log.write("context: unparseable codex tool call")
      exit(0)
    }
    guard checkpointInput.agentID == nil, settings.contextCheckpoints.enabled else {
      exit(0)
    }
    guard ContextCheckpointStore.isValidSessionID(checkpointInput.sessionID) else {
      exit(0)
    }
    guard let transcriptPath = checkpointInput.transcriptPath,
      let codexReading = CodexUsageReader.read(rolloutURL: URL(fileURLWithPath: transcriptPath))
    else {
      exit(0)
    }
    let store = ContextCheckpointStore(directory: paths.contextCheckpointsDirectory)
    guard
      let plan = plan(
        codexReading: codexReading, checkpointInput: checkpointInput,
        transcriptPath: transcriptPath, store: store, settings: settings, now: Date(),
        levels: [.stop], log: log),
      case .inject(let text) = plan.decision
    else {
      exit(0)
    }
    if let data = CodexAdapter.encodeContext(text, eventName: ContextHookSetup.toolEventName) {
      ReplyWriter.write(data, to: .standardOutput)
    }
    log.write("context: codex \(codexReading.tokens) tokens after a tool call, stop fired")
    log.write("outcome: context note (codex, stop, after a tool call)")
    exit(0)
  }

  private static func plan(
    codexReading: CodexContextReading, checkpointInput: ContextCheckpointInput,
    transcriptPath: String, store: ContextCheckpointStore, settings: Settings, now: Date,
    levels: [ContextLevel], log: EventLog
  ) -> ContextCheckpointPlan? {
    let sessionID = checkpointInput.sessionID
    let checkpointSettings = settings.contextCheckpoints.forCodex(
      windowTokens: codexReading.windowTokens)
    let reading = ContextReading(
      tokens: codexReading.tokens, modelID: nil, hasMillionTokenWindow: false,
      compactionID: nil)
    do {
      return try store.withLock(sessionID: sessionID) {
        let previous = store.load(sessionID: sessionID) ?? .fresh(now: now)
        let plan = ContextCheckpointPlanner.plan(
          reading: reading, previous: previous, settings: checkpointSettings,
          transcriptPath: transcriptPath,
          project: ApprovalRequest.projectName(cwd: checkpointInput.cwd), now: now,
          levels: levels)
        try store.save(plan.state, sessionID: sessionID)
        return plan
      }
    } catch {
      log.write("context: codex state not saved: \(error)")
      exit(0)
    }
  }
}
