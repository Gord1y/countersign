import Dispatch
import Foundation
import os

final class TerminationCleanup: Sendable {
  static let shared = TerminationCleanup()
  static let terminationSignals: [Int32] = [SIGTERM, SIGINT, SIGHUP]

  private let paths: OSAllocatedUnfairLock<[String]>
  private let sources: [any DispatchSourceSignal]

  private init() {
    let paths = OSAllocatedUnfairLock<[String]>(initialState: [])
    let queue = DispatchQueue(label: "Countersign.TerminationCleanup")
    self.paths = paths
    self.sources = Self.terminationSignals.map { signalNumber in
      Self.install(signalNumber, on: queue, removing: paths)
    }
  }

  func register(_ file: URL) {
    paths.withLock { $0.append(file.path) }
  }

  private static func install(
    _ signalNumber: Int32,
    on queue: DispatchQueue,
    removing paths: OSAllocatedUnfairLock<[String]>
  ) -> any DispatchSourceSignal {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: queue)
    source.setEventHandler {
      for path in paths.withLock({ $0 }) {
        unlink(path)
      }
      _exit(0)
    }
    source.resume()
    return source
  }
}
