import Foundation

public struct HostWiringUpdate: Sendable, Equatable {
  public let otherExecutablePaths: [String]
  public let otherArguments: [String]
  public let missingEvents: [String]
  public let addsWaitingEntry: Bool
  public let addsContextEntry: Bool

  public init(
    otherExecutablePaths: [String], otherArguments: [String] = [], missingEvents: [String] = [],
    addsWaitingEntry: Bool = false, addsContextEntry: Bool = false
  ) {
    self.addsContextEntry = addsContextEntry
    self.otherExecutablePaths = otherExecutablePaths
    self.otherArguments = otherArguments
    self.missingEvents = missingEvents
    self.addsWaitingEntry = addsWaitingEntry
  }
}

public enum HostWiringStatus: Sendable, Equatable {
  case notInstalled
  case notWired
  case wired
  case needsUpdate(HostWiringUpdate)
  case unusable(String)
}

public enum HostWiringAction: Sendable, Equatable {
  case wire
  case update
  case remove

  public var title: String {
    switch self {
    case .wire: return "Wire"
    case .update: return "Update"
    case .remove: return "Remove"
    }
  }

  public var uninstalls: Bool {
    self == .remove
  }
}

public enum HostWiring {
  public static func status(
    host: Host, directoryExists: Bool, file: Doctor.FileState, stablePath: String,
    addsWaitingEntry: Bool, addsContextEntry: Bool = false
  ) -> HostWiringStatus {
    guard directoryExists else { return .notInstalled }
    let bytes: [UInt8]
    switch file {
    case .missing:
      return .notWired
    case .unreadable(let reason):
      return .unusable(reason)
    case .bytes(let read):
      bytes = read
    }
    guard !HookSetup.isBlank(bytes) else { return .notWired }
    let root: JSONSpanNode
    let installed: [UInt8]
    do {
      root = try JSONSpanReader.parse(bytes)
      installed = try HookSetup.install(
        into: bytes, host: host, executablePath: stablePath, addsWaitingEntry: addsWaitingEntry,
        addsContextEntry: addsContextEntry)
    } catch {
      return .unusable(SetupRun.describe(error))
    }
    let hooks = HookSetup.hookNodes(in: root, host: host)
    guard !hooks.isEmpty else { return .notWired }
    guard installed != bytes else { return .wired }
    var otherPaths: [String] = []
    var otherArguments: [String] = []
    for words in hooks.map(commandWords(of:)) {
      if let path = words.first, path != stablePath, !otherPaths.contains(path) {
        otherPaths.append(path)
      }
      let arguments = Array(words.dropFirst())
      let shown = arguments.joined(separator: " ")
      if arguments != HookCommand.arguments(for: host), !otherArguments.contains(shown) {
        otherArguments.append(shown)
      }
    }
    let missing = host == .cursor ? CursorHookSetup.missingEvents(in: root) : []
    let missingWaitingEntry =
      addsWaitingEntry && WaitingHookSetup.hookNodes(in: root, host: host).isEmpty
    let missingContextEntry =
      host == .claude && addsContextEntry
      && HookSetup.sites(in: root, event: ContextHookSetup.eventName).isEmpty
    return .needsUpdate(
      HostWiringUpdate(
        otherExecutablePaths: otherPaths, otherArguments: otherArguments, missingEvents: missing,
        addsWaitingEntry: missingWaitingEntry, addsContextEntry: missingContextEntry))
  }

  public static func action(for status: HostWiringStatus) -> HostWiringAction? {
    switch status {
    case .notWired: return .wire
    case .needsUpdate: return .update
    case .wired: return .remove
    case .notInstalled, .unusable: return nil
    }
  }

  public static func title(for status: HostWiringStatus) -> String {
    switch status {
    case .notInstalled: return "Not installed"
    case .notWired: return "Not wired"
    case .wired: return "Wired"
    case .needsUpdate: return "Needs an update"
    case .unusable: return "Can't be set up"
    }
  }

  public static func detail(for status: HostWiringStatus, host: Host) -> String? {
    switch status {
    case .needsUpdate(let update):
      var parts: [String] = []
      if !update.otherExecutablePaths.isEmpty {
        parts.append("points at \(update.otherExecutablePaths.joined(separator: ", "))")
      }
      if !update.otherArguments.isEmpty {
        let canonical = HookCommand.arguments(for: host).joined(separator: " ")
        parts.append(
          "runs \(update.otherArguments.joined(separator: ", ")) rather than \(canonical)")
      }
      if !update.missingEvents.isEmpty {
        parts.append("adds the entry under \(update.missingEvents.joined(separator: " and "))")
      }
      if update.addsWaitingEntry {
        parts.append("adds the Stop entry for waiting-agent notices")
      }
      if update.addsContextEntry {
        parts.append("adds the UserPromptSubmit entry for context checkpoints")
      }
      if parts.isEmpty {
        switch host {
        case .codex:
          parts.append("refreshes the entry's timeout and status message")
        case .claude:
          parts.append("refreshes the timeout and async settings of Countersign's entries")
        case .cursor, .antigravity:
          parts.append("refreshes the entry's timeout")
        }
      }
      let sentence = parts.joined(separator: "; ")
      return sentence.prefix(1).uppercased() + sentence.dropFirst()
    case .unusable(let reason):
      return reason
    case .notInstalled, .notWired, .wired:
      return nil
    }
  }

  private static func commandWords(of hook: JSONSpanNode) -> [String] {
    let command = hook.member(named: "command")?.value.stringValue ?? ""
    return HookCommand.words(in: Array(command.unicodeScalars), limit: Int.max).map(\.value)
  }
}
