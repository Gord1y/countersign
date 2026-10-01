import AppKit
import ApprovalCore
import Darwin
import Foundation

@MainActor
enum WaitingNoticeCommand {
  static func run(_ arguments: [String]) -> Never {
    signal(SIGPIPE, SIG_IGN)
    let paths = AppPaths.standard
    let log = EventLog(file: paths.logFile)
    log.redirectStandardError()

    guard arguments.count == 1 else { exit(0) }
    let recordFile = URL(fileURLWithPath: arguments[0])
    let store = WaitingStore(directory: recordFile.deletingLastPathComponent())
    guard let record = store.load(recordFile),
      let lock = try? ExclusiveFileLock.acquire(store.lockFile(for: record))
    else { exit(0) }

    let configFile = ConfigFileLoader.load(paths: paths, soundNames: SystemSounds.installedNames)
      .file
    let settings = Settings.resolve(file: configFile, host: record.host)
    CountersignPalette.use(settings.accentColor)

    let app = PanelApplication(log: { log.write($0) })
    let watch = WaitingNoticeWatch(
      record: record, recordFile: recordFile, store: store, lock: lock, paths: paths,
      settings: settings, log: log)
    app.afterLaunch { watch.start() }
    app.run()
    exit(0)
  }
}

@MainActor
private final class WaitingNoticeWatch: NSObject {
  private static let tickInterval: TimeInterval = 1

  private let recordFile: URL
  private let store: WaitingStore
  private let log: EventLog
  private let delay: TimeInterval
  private let appearance: AppearanceChoice
  private let pauseSwitch: PauseSwitch
  private let quietState: QuietState
  private let queue: TicketQueue
  private var lock: ExclusiveFileLock
  private var record: WaitingRecord
  private var transcript: TranscriptWatch
  private var card: CornerCard?
  private var lastAgentAppFrontmostAt: Date?
  private var loggedHold: WaitingNoticeHold?
  private var isLeaving = false
  private var timer: Timer?
  private var screenObserver: (any NSObjectProtocol)?

  init(
    record: WaitingRecord, recordFile: URL, store: WaitingStore, lock: ExclusiveFileLock,
    paths: AppPaths, settings: Settings, log: EventLog
  ) {
    self.record = record
    self.recordFile = recordFile
    self.store = store
    self.lock = lock
    self.log = log
    self.delay = TimeInterval(settings.waitingNoticeMinutes * 60)
    self.appearance = settings.appearance
    self.pauseSwitch = PauseSwitch(file: paths.pauseFile)
    self.quietState = QuietState(
      paths: paths, schedule: QuietSchedule(windows: settings.quietHours))
    self.queue = TicketQueue(directory: paths.queueDirectory, lockFile: paths.displayLockFile)
    self.transcript = TranscriptWatch(record: record)
    super.init()
  }

  func start() {
    logWaiting()
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.card?.followScreenChange() }
    }
    let timer = Timer(
      timeInterval: Self.tickInterval, target: self, selector: #selector(tick), userInfo: nil,
      repeats: true)
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
    tick()
  }

  @objc func tick() {
    guard !isLeaving else { return }
    guard let current = store.load(recordFile) else {
      hide()
      log.write("notice: closed (working again)")
      exit(0)
    }
    if current.recordedAt != record.recordedAt {
      startOver(with: current)
    }
    apply(WaitingNoticeClock.decide(sample(now: Date())))
  }

  private func sample(now: Date) -> WaitingNoticeSample {
    let agentAppFrontmost = isAgentAppFrontmost()
    if agentAppFrontmost {
      lastAgentAppFrontmostAt = now
    }
    return WaitingNoticeSample(
      now: now, recordedAt: record.recordedAt, delay: delay, isShown: card != nil,
      agentAlive: isAgentAlive(), paused: pauseSwitch.isPaused,
      quiet: quietState.activeUntil(now: now) != nil, agentAppFrontmost: agentAppFrontmost,
      lastAgentAppFrontmostAt: lastAgentAppFrontmostAt,
      sessionHasLiveTicket: sessionHasLiveTicket(), resumed: transcript.resumed(now: now))
  }

  private func apply(_ step: WaitingNoticeStep) {
    switch step {
    case .show:
      show()
    case .wait(let hold):
      note(hold)
    case .hide(let hold):
      hide()
      loggedHold = hold
      log.write("notice: hidden (\(hold.rawValue))")
    case .close(let reason):
      close(reason)
    }
  }

  private func show() {
    guard card == nil,
      let card = CornerCard.inFreeSlot(
        of: store, model: .waitingNotice(record: record), accessibilityTitle: "Countersign notice",
        appearance: appearance, onAction: { [weak self] in self?.goThere() },
        onDismiss: { [weak self] in self?.close(.dismissed) })
    else { return }
    self.card = card
    card.show()
    loggedHold = nil
    log.write("notice: shown")
  }

  private func hide() {
    card?.close()
    card = nil
  }

  private func note(_ hold: WaitingNoticeHold?) {
    guard hold != loggedHold else { return }
    loggedHold = hold
    if let hold {
      log.write("notice: held (\(hold.rawValue))")
    }
  }

  private func close(_ reason: WaitingNoticeClose) {
    hide()
    isLeaving = false
    log.write("notice: closed (\(reason.rawValue))")
    let latest = store.load(recordFile)
    if let latest, latest.recordedAt != record.recordedAt {
      startOver(with: latest)
      return
    }
    if latest != nil {
      store.delete(recordFile)
    }
    lock.release()
    if let arrived = store.load(recordFile),
      let relocked = try? ExclusiveFileLock.acquire(store.lockFile(for: arrived))
    {
      lock = relocked
      startOver(with: arrived)
      return
    }
    exit(0)
  }

  private func startOver(with newer: WaitingRecord) {
    hide()
    record = newer
    transcript = TranscriptWatch(record: newer)
    lastAgentAppFrontmostAt = nil
    loggedHold = nil
    logWaiting()
  }

  private func logWaiting() {
    log.write(
      "notice: waiting \(record.host.rawValue) \(record.projectName) (\(record.reason.rawValue))")
  }

  private func goThere() {
    guard let url = agentAppURL() else {
      close(.goThere)
      return
    }
    hide()
    isLeaving = true
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
      [weak self] _, _ in
      Task { @MainActor in self?.close(.goThere) }
    }
  }

  private func agentAppURL() -> URL? {
    guard let bundleID = record.appBundleID else { return nil }
    if let pid = record.appPID, let app = NSRunningApplication(processIdentifier: pid),
      !app.isTerminated, app.bundleIdentifier == bundleID, let url = app.bundleURL
    {
      return url
    }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
  }

  private func isAgentAppFrontmost() -> Bool {
    guard let bundleID = record.appBundleID else { return false }
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
  }

  private func isAgentAlive() -> Bool {
    guard let pid = record.agentPID else { return true }
    return ProcessLiveness.isAlive(pid: pid, processStart: record.agentStart)
  }

  private func sessionHasLiveTicket() -> Bool {
    queue.liveTickets().contains { ticket in
      guard let summary = ticket.summary, summary.host == record.host, !summary.isTestPanel
      else { return false }
      guard let agentPID = record.agentPID else { return summary.project == record.projectName }
      return ProcessAncestry.chain(from: ticket.pid).contains(agentPID)
    }
  }
}

private struct TranscriptWatch {
  private let host: ApprovalCore.Host
  private let path: String?
  private let settledAt: Date
  private var baseline: UInt64?

  init(record: WaitingRecord) {
    host = record.host
    path = record.transcriptPath
    settledAt = record.recordedAt.addingTimeInterval(TimeInterval(TranscriptGrowth.settleSeconds))
  }

  mutating func resumed(now: Date) -> Bool {
    guard let path, now >= settledAt, let size = Self.size(ofFileAt: path) else { return false }
    guard let baseline, size >= baseline else {
      baseline = size
      return false
    }
    guard size > baseline else { return false }
    let count = min(size - baseline, UInt64(TranscriptGrowth.maximumReadBytes))
    guard let appended = Self.read(path, from: baseline, count: Int(count)) else { return false }
    return TranscriptGrowth.resumed(host: host, appended: appended)
  }

  private static func size(ofFileAt path: String) -> UInt64? {
    var info = stat()
    guard stat(path, &info) == 0, info.st_size >= 0 else { return nil }
    return UInt64(info.st_size)
  }

  private static func read(_ path: String, from offset: UInt64, count: Int) -> Data? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    do {
      try handle.seek(toOffset: offset)
      return try handle.read(upToCount: count)
    } catch {
      return nil
    }
  }
}
