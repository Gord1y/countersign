import Foundation

public enum WaitingHookSetup {
  static let eventName = "Stop"
  static let cursorEventName = "stop"
  static let antigravityHookName = "countersign-waiting"
  static let antigravityMatcher = "*"
  static let timeoutSeconds = 30

  public static let supportedHosts: [Host] = [.claude, .codex, .cursor, .antigravity]

  static func eventName(for host: Host) -> String {
    host == .cursor ? cursorEventName : eventName
  }

  public static func install(into original: [UInt8]?, host: Host, executablePath: String) throws
    -> [UInt8]
  {
    guard HookCommand.isCountersignExecutable(executablePath) else {
      throw HookSetupError.unrecognizableExecutable(executablePath)
    }
    let source = original.flatMap { HookSetup.isBlank($0) ? nil : $0 } ?? HookSetup.emptyDocument
    var document = try JSONSourceDocument(bytes: source)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    switch host {
    case .claude, .codex:
      try installGrouped(into: &document, host: host, executablePath: executablePath)
    case .cursor:
      try installCursor(into: &document, executablePath: executablePath)
    case .antigravity:
      try installAntigravity(into: &document, executablePath: executablePath)
    }
    return document.bytes
  }

  public static func refresh(into original: [UInt8], host: Host, executablePath: String) throws
    -> [UInt8]
  {
    guard !HookSetup.isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    try refreshEntries(in: &document, host: host, executablePath: executablePath)
    return document.bytes
  }

  public static func uninstall(from original: [UInt8]?, host: Host) throws -> [UInt8]? {
    switch host {
    case .claude, .codex:
      return try HookSetup.removeEntries(from: original, event: eventName)
    case .cursor:
      return try uninstallCursor(from: original)
    case .antigravity:
      return try uninstallAntigravity(from: original)
    }
  }

  public static func entries(in bytes: [UInt8], host: Host) -> [ContextHookEntry] {
    guard let root = try? JSONSpanReader.parse(bytes) else { return [] }
    return hookNodes(in: root, host: host).map { hook in
      ContextHookEntry(
        command: hook.member(named: "command")?.value.stringValue ?? "",
        isAsync: ContextHookSetup.isAsync(hook),
        timeoutSeconds: hook.member(named: "timeout")?.value.numberValue)
    }
  }

  static func hookNodes(in root: JSONSpanNode, host: Host) -> [JSONSpanNode] {
    switch host {
    case .claude, .codex:
      return HookSetup.sites(in: root, event: eventName).map(\.hook)
    case .cursor:
      return cursorSites(in: root).map(\.hook)
    case .antigravity:
      guard let ours = root.member(named: antigravityHookName)?.value,
        let hook = AntigravityHookSetup.entry(inSetupShape: ours, event: eventName)
      else { return [] }
      return [hook]
    }
  }

  private static func installGrouped(
    into document: inout JSONSourceDocument, host: Host, executablePath: String
  ) throws {
    let group = groupFragment(host: host, executablePath: executablePath)
    guard let hooks = try HookSetup.hooksObject(in: document.root) else {
      let event = JSONFragmentMember(key: eventName, value: .array([group]))
      try document.appendMember(
        JSONFragmentMember(key: "hooks", value: .object([event])), to: document.root)
      return
    }
    guard let groups = try HookSetup.eventArray(in: hooks, event: eventName) else {
      try document.appendMember(
        JSONFragmentMember(key: eventName, value: .array([group])), to: hooks)
      return
    }
    guard !HookSetup.sites(in: document.root, event: eventName).isEmpty else {
      try document.appendElement(group, to: groups)
      return
    }
    try refreshEntries(in: &document, host: host, executablePath: executablePath)
  }

  private static func installCursor(
    into document: inout JSONSourceDocument, executablePath: String
  ) throws {
    let entry = hookFragment(host: .cursor, executablePath: executablePath)
    try CursorHookSetup.addVersionIfMissing(to: &document)
    guard let hooks = try CursorHookSetup.hooksObject(in: document.root) else {
      let event = JSONFragmentMember(key: cursorEventName, value: .array([entry]))
      try document.appendMember(
        JSONFragmentMember(key: CursorHookSetup.hooksKey, value: .object([event])),
        to: document.root)
      return
    }
    guard let entries = try CursorHookSetup.eventArray(named: cursorEventName, in: hooks) else {
      try document.appendMember(
        JSONFragmentMember(key: cursorEventName, value: .array([entry])), to: hooks)
      return
    }
    guard !cursorSites(in: document.root).isEmpty else {
      try document.appendElement(entry, to: entries)
      return
    }
    try refreshEntries(in: &document, host: .cursor, executablePath: executablePath)
  }

  private static func installAntigravity(
    into document: inout JSONSourceDocument, executablePath: String
  ) throws {
    let namedHook = antigravityHookFragment(executablePath: executablePath)
    guard let ours = document.root.member(named: antigravityHookName)?.value else {
      try document.appendMember(
        JSONFragmentMember(key: antigravityHookName, value: namedHook), to: document.root)
      return
    }
    guard AntigravityHookSetup.entry(inSetupShape: ours, event: eventName) != nil else {
      try document.replaceValue(ours, with: namedHook)
      return
    }
    try refreshEntries(in: &document, host: .antigravity, executablePath: executablePath)
  }

  private static func uninstallCursor(from original: [UInt8]?) throws -> [UInt8]? {
    guard let original, !HookSetup.isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    guard let hooks = try CursorHookSetup.hooksObject(in: document.root),
      try CursorHookSetup.eventArray(named: cursorEventName, in: hooks) != nil
    else { return document.bytes }
    while let site = cursorSites(in: document.root).first {
      if let count = site.entries.elements?.count, count > 1 {
        try document.removeElement(at: site.entryIndex, from: site.entries)
      } else {
        try document.removeMember(at: site.eventMemberIndex, from: site.hooksObject)
      }
    }
    return document.bytes
  }

  private static func uninstallAntigravity(from original: [UInt8]?) throws -> [UInt8]? {
    guard let original, !HookSetup.isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    while let index = document.root.memberIndex(named: antigravityHookName) {
      try document.removeMember(at: index, from: document.root)
    }
    return document.bytes
  }

  private static func cursorSites(in root: JSONSpanNode) -> [CursorHookSite] {
    guard let hooksObject = root.member(named: CursorHookSetup.hooksKey)?.value,
      let eventMemberIndex = hooksObject.memberIndex(named: cursorEventName),
      let entries = hooksObject.member(named: cursorEventName)?.value,
      let entryNodes = entries.elements
    else { return [] }
    return entryNodes.enumerated().compactMap { entryIndex, entry in
      guard CursorHookSetup.isCountersignEntry(entry) else { return nil }
      return CursorHookSite(
        hooksObject: hooksObject, eventName: cursorEventName, eventMemberIndex: eventMemberIndex,
        entries: entries, entryIndex: entryIndex, hook: entry)
    }
  }

  private static func hookFragment(host: Host, executablePath: String) -> JSONFragment {
    var members: [JSONFragmentMember] = []
    if host != .cursor {
      members.append(JSONFragmentMember(key: "type", value: .string("command")))
    }
    members.append(
      JSONFragmentMember(
        key: "command",
        value: .string(
          HookCommand.command(host: host, executablePath: executablePath, event: .waiting))))
    if host == .claude {
      members.append(JSONFragmentMember(key: "async", value: .bool(true)))
    }
    members.append(JSONFragmentMember(key: "timeout", value: .integer(timeoutSeconds)))
    return .object(members)
  }

  private static func groupFragment(host: Host, executablePath: String) -> JSONFragment {
    .object([
      JSONFragmentMember(
        key: "hooks",
        value: .array([hookFragment(host: host, executablePath: executablePath)]))
    ])
  }

  private static func antigravityHookFragment(executablePath: String) -> JSONFragment {
    let group = JSONFragment.object([
      JSONFragmentMember(key: "matcher", value: .string(antigravityMatcher)),
      JSONFragmentMember(
        key: "hooks",
        value: .array([hookFragment(host: .antigravity, executablePath: executablePath)])),
    ])
    return .object([JSONFragmentMember(key: eventName, value: .array([group]))])
  }

  private static func refreshEntries(
    in document: inout JSONSourceDocument, host: Host, executablePath: String
  ) throws {
    for index in 0..<hookNodes(in: document.root, host: host).count {
      try updateCommand(ofHook: index, in: &document, host: host, executablePath: executablePath)
      if host == .claude {
        try ensureMember("async", ofHook: index, in: &document, host: host, fragment: .bool(true)) {
          $0.content == .bool(true)
        }
      }
      try ensureMember(
        "timeout", ofHook: index, in: &document, host: host, fragment: .integer(timeoutSeconds)
      ) { $0.numberValue == Double(timeoutSeconds) }
    }
  }

  private static func hookNode(_ index: Int, host: Host, in document: JSONSourceDocument)
    -> JSONSpanNode?
  {
    let all = hookNodes(in: document.root, host: host)
    return all.indices.contains(index) ? all[index] : nil
  }

  private static func updateCommand(
    ofHook index: Int, in document: inout JSONSourceDocument, host: Host, executablePath: String
  ) throws {
    guard
      let command = hookNode(index, host: host, in: document)?.member(named: "command")?.value,
      let text = command.stringValue,
      !HookCommand.isCommand(text, running: executablePath, for: host, event: .waiting)
    else { return }
    try document.replaceValue(
      command,
      with: .string(
        HookCommand.command(host: host, executablePath: executablePath, event: .waiting)))
  }

  private static func ensureMember(
    _ key: String, ofHook index: Int, in document: inout JSONSourceDocument, host: Host,
    fragment: JSONFragment, matches: (JSONSpanNode) -> Bool
  ) throws {
    guard let hook = hookNode(index, host: host, in: document) else { return }
    guard let existing = hook.member(named: key) else {
      try document.appendMember(JSONFragmentMember(key: key, value: fragment), to: hook)
      return
    }
    guard !matches(existing.value) else { return }
    try document.replaceValue(existing.value, with: fragment)
  }
}
