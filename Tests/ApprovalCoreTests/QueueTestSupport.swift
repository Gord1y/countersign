import Darwin
import Foundation
import Testing
import os

@testable import ApprovalCore

struct TemporaryQueue {
  let directory: URL
  let lockFile: URL
  let queue: TicketQueue

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-queue-\(UUID().uuidString)")
    lockFile = directory.appendingPathComponent("display.lock")
    queue = TicketQueue(directory: directory, lockFile: lockFile)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }

  func fileExists(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
  }

  func ticketNames() -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.filter { Ticket.parseFileName($0) != nil }.sorted()
  }

  @discardableResult
  func writeTicket(timestamp: UInt64, pid: Int32, content: Data?) throws -> String {
    let name = Ticket.fileName(timestamp: timestamp, pid: pid)
    try (content ?? Data()).write(to: directory.appendingPathComponent(name))
    return name
  }

  func writeTicket(timestamp: UInt64, pid: Int32, processStart: UInt64?) throws -> String {
    let content = TicketContent(processStart: processStart, summary: .probe)
    return try writeTicket(
      timestamp: timestamp, pid: pid, content: JSONEncoder().encode(content))
  }
}

extension TicketSummary {
  static let probe = TicketSummary(host: .claude, project: "probe", tool: "Bash", agentType: nil)
}

final class ProbeOutput: Sendable {
  private struct State {
    var text = ""
    var isClosed = false
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  func append(_ data: Data) {
    let chunk = String(decoding: data, as: UTF8.self)
    state.withLock { $0.text += chunk }
  }

  func close() {
    state.withLock { $0.isClosed = true }
  }

  var lines: [String] {
    state.withLock { $0.text }.split(separator: "\n").map(String.init)
  }

  var isClosed: Bool {
    state.withLock { $0.isClosed }
  }
}

final class ProbeProcess {
  let tag: String
  let output = ProbeOutput()
  private let process = Process()
  private let input = Pipe()

  static var binary: URL {
    Bundle.module.bundleURL.deletingLastPathComponent().appendingPathComponent("ticket-probe")
  }

  static func requireBinary() throws {
    let path = binary.path
    try #require(
      FileManager.default.isExecutableFile(atPath: path),
      "ticket-probe is missing at \(path); run `swift build` before `swift test`"
    )
  }

  static func hold(_ temporary: TemporaryQueue, tag: String) throws -> ProbeProcess {
    try ProbeProcess(
      tag: tag,
      arguments: ["hold", temporary.directory.path, temporary.lockFile.path, tag]
    )
  }

  static func chain(_ temporary: TemporaryQueue, tag: String) throws -> ProbeProcess {
    try ProbeProcess(
      tag: tag,
      arguments: ["chain", temporary.directory.path, temporary.lockFile.path, tag]
    )
  }

  func line(startingWith prefix: String) -> String? {
    output.lines.first { $0.hasPrefix(prefix) }
  }

  func number(after prefix: String) -> Int64? {
    line(startingWith: prefix).flatMap { Int64($0.dropFirst(prefix.count)) }
  }

  static func enqueue(_ temporary: TemporaryQueue) throws -> ProbeProcess {
    try ProbeProcess(
      tag: "enqueue",
      arguments: ["enqueue", temporary.directory.path, temporary.lockFile.path]
    )
  }

  private init(tag: String, arguments: [String]) throws {
    try Self.requireBinary()
    self.tag = tag
    let standardOutput = Pipe()
    let output = output
    standardOutput.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        output.close()
      } else {
        output.append(data)
      }
    }
    _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    process.executableURL = Self.binary
    process.arguments = arguments
    process.standardInput = input
    process.standardOutput = standardOutput
    process.standardError = FileHandle.nullDevice
    try process.run()
  }

  enum Termination: Equatable {
    case exited(Int32)
    case signaled(Int32)
  }

  var pid: Int32 { process.processIdentifier }
  var isRunning: Bool { process.isRunning }

  var termination: Termination? {
    guard !process.isRunning else { return nil }
    switch process.terminationReason {
    case .exit: return .exited(process.terminationStatus)
    case .uncaughtSignal: return .signaled(process.terminationStatus)
    @unknown default: return nil
    }
  }

  var isDisplaying: Bool {
    let lines = output.lines
    return lines.contains("displaying \(tag)") && !lines.contains("released \(tag)")
  }

  var hasDisplayed: Bool { output.lines.contains("displaying \(tag)") }
  var hasReleased: Bool { output.lines.contains("released \(tag)") }

  func sendLine() {
    try? input.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
  }

  func send(_ signalNumber: Int32) {
    Darwin.kill(process.processIdentifier, signalNumber)
  }

  func waitForExit() async -> Bool {
    await eventually { !process.isRunning }
  }

  func forceStop() {
    guard process.isRunning else { return }
    Darwin.kill(process.processIdentifier, SIGKILL)
    waitBriefly(for: process)
  }
}

final class ProbeGroup {
  private(set) var probes: [ProbeProcess] = []

  func add(_ probe: ProbeProcess) -> ProbeProcess {
    probes.append(probe)
    return probe
  }

  func forceStopAll() {
    for probe in probes {
      probe.forceStop()
    }
  }

  var displaying: [ProbeProcess] { probes.filter(\.isDisplaying) }
}

func eventually(
  within timeout: Duration = .seconds(5),
  _ condition: () -> Bool
) async -> Bool {
  let clock = SuspendingClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if condition() { return true }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return condition()
}

func holds(
  for duration: Duration,
  _ condition: () -> Bool
) async -> Bool {
  let clock = SuspendingClock()
  let deadline = clock.now.advanced(by: duration)
  while clock.now < deadline {
    if !condition() { return false }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return condition()
}

struct ProcessWaitTimedOut: Error {}

@discardableResult
func waitBriefly(for process: Process, within timeout: Duration = .seconds(5)) -> Bool {
  let clock = SuspendingClock()
  let deadline = clock.now.advanced(by: timeout)
  while process.isRunning, clock.now < deadline {
    Thread.sleep(forTimeInterval: 0.01)
  }
  return !process.isRunning
}

enum ChildProcess {
  enum SpawnError: Error {
    case failed(Int32)
  }

  static func spawnInheritingDescriptors(_ path: String, _ arguments: [String]) throws -> pid_t {
    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = ([path] + arguments).map { strdup($0) } + [nil]
    let envp: [UnsafeMutablePointer<CChar>?] = [nil]
    defer {
      for argument in argv {
        free(argument)
      }
    }
    let result = posix_spawn(&pid, path, nil, nil, argv, envp)
    guard result == 0 else { throw SpawnError.failed(result) }
    return pid
  }

  static func isZombie(_ pid: pid_t) -> Bool {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    let result = mib.withUnsafeMutableBufferPointer { mibPointer in
      sysctl(mibPointer.baseAddress, u_int(mibPointer.count), &info, &size, nil, 0)
    }
    guard result == 0, size == MemoryLayout<kinfo_proc>.stride, info.kp_proc.p_pid == pid else {
      return false
    }
    return info.kp_proc.p_stat == SZOMB
  }

  static func deadPid() throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    guard waitBriefly(for: process) else {
      Issue.record(
        "/usr/bin/true did not exit before the wait deadline; deadPid() cannot guarantee the pid is dead"
      )
      throw ProcessWaitTimedOut()
    }
    return process.processIdentifier
  }

  static func reap(_ pid: pid_t) {
    Darwin.kill(pid, SIGKILL)
    var status: Int32 = 0
    waitpid(pid, &status, 0)
  }

  static func openVnodePaths(of pid: pid_t) -> [String] {
    let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard needed > 0 else { return [] }
    let stride = MemoryLayout<proc_fdinfo>.stride
    var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride)
    let used = descriptors.withUnsafeMutableBytes { buffer in
      proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
    }
    guard used > 0 else { return [] }
    return descriptors.prefix(Int(used) / stride).compactMap { descriptor in
      guard descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return nil }
      var info = vnode_fdinfowithpath()
      let size = Int32(MemoryLayout<vnode_fdinfowithpath>.stride)
      let read = proc_pidfdinfo(
        pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size)
      guard read == size else { return nil }
      return withUnsafeBytes(of: info.pvip.vip_path) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
      }
    }
  }
}
