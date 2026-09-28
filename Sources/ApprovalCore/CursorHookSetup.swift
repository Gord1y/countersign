import Foundation

struct CursorHookSite: Sendable, Equatable {
  let hooksObject: JSONSpanNode
  let eventName: String
  let eventMemberIndex: Int
  let entries: JSONSpanNode
  let entryIndex: Int
  let hook: JSONSpanNode
}

enum CursorHookSetup {
  static let versionKey = "version"
  static let version = 1
  static let hooksKey = "hooks"

  static func install(into original: [UInt8]?, executablePath: String) throws -> [UInt8] {
    let source = original.flatMap { HookSetup.isBlank($0) ? nil : $0 } ?? HookSetup.emptyDocument
    var document = try JSONSourceDocument(bytes: source)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    let entry = entryFragment(executablePath: executablePath)
    guard let hooks = try hooksObject(in: document.root) else {
      try addVersionIfMissing(to: &document)
      let events = CursorAdapter.events.map {
        JSONFragmentMember(key: $0, value: .array([entry]))
      }
      try document.appendMember(
        JSONFragmentMember(key: hooksKey, value: .object(events)), to: document.root)
      return document.bytes
    }
    for event in CursorAdapter.events {
      _ = try eventArray(named: event, in: hooks)
    }
    try addVersionIfMissing(to: &document)
    try HookSetup.refreshEntries(in: &document, host: .cursor, executablePath: executablePath)
    for event in missingEvents(in: document.root) {
      let currentHooks = document.root.member(named: hooksKey)?.value
      if let entries = currentHooks?.member(named: event)?.value {
        try document.appendElement(entry, to: entries)
      } else if let currentHooks {
        try document.appendMember(
          JSONFragmentMember(key: event, value: .array([entry])), to: currentHooks)
      }
    }
    return document.bytes
  }

  static func uninstall(from original: [UInt8]?) throws -> [UInt8]? {
    guard let original, !HookSetup.isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    guard let hooks = try hooksObject(in: document.root) else { return document.bytes }
    for event in CursorAdapter.events {
      _ = try eventArray(named: event, in: hooks)
    }
    while let site = sites(in: document.root).first {
      if let count = site.entries.elements?.count, count > 1 {
        try document.removeElement(at: site.entryIndex, from: site.entries)
      } else {
        try document.removeMember(at: site.eventMemberIndex, from: site.hooksObject)
      }
    }
    return document.bytes
  }

  static func sites(in root: JSONSpanNode) -> [CursorHookSite] {
    guard let hooksObject = root.member(named: hooksKey)?.value else { return [] }
    var result: [CursorHookSite] = []
    for event in CursorAdapter.events {
      guard let eventMemberIndex = hooksObject.memberIndex(named: event),
        let entries = hooksObject.member(named: event)?.value,
        let entryNodes = entries.elements
      else { continue }
      for (entryIndex, entry) in entryNodes.enumerated() where isCountersignEntry(entry) {
        result.append(
          CursorHookSite(
            hooksObject: hooksObject, eventName: event, eventMemberIndex: eventMemberIndex,
            entries: entries, entryIndex: entryIndex, hook: entry))
      }
    }
    return result
  }

  static func missingEvents(in root: JSONSpanNode) -> [String] {
    let wired = Set(sites(in: root).map(\.eventName))
    return CursorAdapter.events.filter { !wired.contains($0) }
  }

  static func isCountersignEntry(_ entry: JSONSpanNode) -> Bool {
    let type = entry.member(named: "type")?.value
    guard type == nil || type?.stringValue == "command",
      let command = entry.member(named: "command")?.value.stringValue
    else { return false }
    return HookCommand.isCountersignHook(command)
  }

  static func entryFragment(executablePath: String) -> JSONFragment {
    .object([
      JSONFragmentMember(
        key: "command",
        value: .string(HookCommand.command(host: .cursor, executablePath: executablePath))),
      JSONFragmentMember(key: "timeout", value: .integer(HookSetup.timeoutSeconds)),
    ])
  }

  private static func addVersionIfMissing(to document: inout JSONSourceDocument) throws {
    guard document.root.member(named: versionKey) == nil else { return }
    try document.appendMember(
      JSONFragmentMember(key: versionKey, value: .integer(version)), to: document.root)
  }

  private static func hooksObject(in root: JSONSpanNode) throws -> JSONSpanNode? {
    guard let hooks = root.member(named: hooksKey)?.value else { return nil }
    guard hooks.members != nil else {
      throw HookSetupError.unexpectedType(key: hooksKey, expected: "an object")
    }
    return hooks
  }

  private static func eventArray(named event: String, in hooks: JSONSpanNode) throws
    -> JSONSpanNode?
  {
    guard let entries = hooks.member(named: event)?.value else { return nil }
    guard entries.elements != nil else {
      throw HookSetupError.unexpectedType(key: "\(hooksKey).\(event)", expected: "an array")
    }
    return entries
  }
}
