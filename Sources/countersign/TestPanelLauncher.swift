import ApprovalCore
import Foundation
import Observation

@MainActor
@Observable
final class TestPanelLauncher {
  enum LaunchError: LocalizedError {
    case noExecutable

    var errorDescription: String? {
      switch self {
      case .noExecutable: return "the countersign executable could not be found"
      }
    }
  }

  static let shared = TestPanelLauncher()

  private var running: Set<Process> = []

  var isRunning: Bool { !running.isEmpty }

  func showRunning() {
    let paths = AppPaths.standard
    let log = EventLog(file: paths.logFile)
    let queue = TicketQueue(directory: paths.queueDirectory, lockFile: paths.displayLockFile)
    let runningPids = Set(running.map { $0.processIdentifier })
    guard let ticket = queue.liveTickets().first(where: { runningPids.contains($0.pid) }) else {
      return
    }
    do {
      if try queue.sendMenuAnswer(.show, toTicketID: ticket.id) {
        log.write("test panel: brought back")
      }
    } catch {
      log.write("test panel: failed to bring back: \(error)")
    }
  }

  func launch(kind: TestPanelKind, onRefusal: @escaping @MainActor (String) -> Void) throws {
    guard running.isEmpty else { return }
    guard let executable = Bundle.main.executableURL else { throw LaunchError.noExecutable }
    let process = Process()
    let errors = Pipe()
    process.executableURL = executable
    process.arguments = ["test-panel", kind.rawValue]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    try process.run()
    running.insert(process)
    let reading = errors.fileHandleForReading
    DispatchQueue.global(qos: .utility).async {
      let output = reading.readDataToEndOfFile()
      process.waitUntilExit()
      let refusal = Self.refusal(
        reason: process.terminationReason, status: process.terminationStatus, output: output)
      Task { @MainActor in
        self.running.remove(process)
        if let refusal {
          onRefusal(refusal)
        }
      }
    }
  }

  nonisolated private static func refusal(
    reason: Process.TerminationReason, status: Int32, output: Data
  ) -> String? {
    guard reason == .exit, status != 0 else { return nil }
    let text = String(decoding: output, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "countersign: "
    let message = text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
    return message.isEmpty ? "it stopped with status \(status)" : message
  }
}
