import Darwin
import Foundation

public struct UpdateCheckState: Sendable, Equatable {
  public var lastAttempt: Date
  public var outcome: UpdateCheckOutcome

  public init(lastAttempt: Date, outcome: UpdateCheckOutcome) {
    self.lastAttempt = lastAttempt
    self.outcome = outcome
  }

  public func reevaluated(currentVersion: String) -> UpdateCheckState {
    guard case .newerAvailable(let version) = outcome else { return self }
    return UpdateCheckState(
      lastAttempt: lastAttempt,
      outcome: UpdateCheck.compare(current: currentVersion, latest: version))
  }

  public static func recording(
    _ outcome: UpdateCheckOutcome, at date: Date, over previous: UpdateCheckState?
  ) -> UpdateCheckState? {
    if case .unknown = outcome { return previous }
    return UpdateCheckState(lastAttempt: date, outcome: outcome)
  }
}

public enum UpdateCheckStateStore {
  public static func load(file: URL) -> UpdateCheckState? {
    guard let data = try? Data(contentsOf: file) else { return nil }
    return decode(data)
  }

  public static func save(_ state: UpdateCheckState, to file: URL) throws {
    let directory = file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let temporary = directory.appendingPathComponent(".\(file.lastPathComponent).tmp")
    try encode(state).write(to: temporary)
    guard rename(temporary.path, file.path) == 0 else {
      let code = errno
      unlink(temporary.path)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }

  static func encode(_ state: UpdateCheckState) -> Data {
    let result: JSONValue
    switch state.outcome {
    case .newerAvailable(let version):
      result = .object(["kind": .string("newerAvailable"), "version": .string(version)])
    case .upToDate:
      result = .object(["kind": .string("upToDate")])
    case .unknown(let reason):
      result = .object(["kind": .string("unknown"), "reason": .string(reason)])
    }
    let root: JSONValue = .object([
      "lastAttempt": .int(Int64(state.lastAttempt.timeIntervalSince1970.rounded())),
      "result": result,
    ])
    return (try? JSONEncoder().encode(root)) ?? Data()
  }

  static func decode(_ data: Data) -> UpdateCheckState? {
    guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
      case .object(let root) = value,
      case .int(let attemptSeconds)? = root["lastAttempt"],
      case .object(let result)? = root["result"],
      case .string(let kind)? = result["kind"]
    else { return nil }
    let lastAttempt = Date(timeIntervalSince1970: TimeInterval(attemptSeconds))
    switch kind {
    case "newerAvailable":
      guard case .string(let version)? = result["version"] else { return nil }
      return UpdateCheckState(lastAttempt: lastAttempt, outcome: .newerAvailable(version: version))
    case "upToDate":
      return UpdateCheckState(lastAttempt: lastAttempt, outcome: .upToDate)
    case "unknown":
      guard case .string(let reason)? = result["reason"] else { return nil }
      return UpdateCheckState(lastAttempt: lastAttempt, outcome: .unknown(reason: reason))
    default:
      return nil
    }
  }
}
