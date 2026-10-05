import Foundation

public enum HookSetupError: Error, Equatable, Sendable, CustomStringConvertible {
  case unexpectedType(key: String, expected: String)
  case unrecognizableExecutable(String)

  public var description: String {
    switch self {
    case .unexpectedType(let key, let expected):
      return "\(key) is not \(expected)"
    case .unrecognizableExecutable(let path):
      return
        "\(path) is not named \(HookCommand.executableName), so its entry could not be found again"
    }
  }
}

struct HookSite: Sendable, Equatable {
  let hooksObject: JSONSpanNode
  let eventMemberIndex: Int
  let groups: JSONSpanNode
  let groupIndex: Int
  let groupHooks: JSONSpanNode
  let hookIndex: Int
  let hook: JSONSpanNode
}

public enum HookSetup {
  public static let eventName = "PermissionRequest"
  public static let timeoutSeconds = 3600
  public static let codexStatusMessage = "Waiting for the approval panel"

  static let emptyDocument = Array("{}\n".utf8)

  public static func install(
    into original: [UInt8]?, host: Host, executablePath: String, addsWaitingEntry: Bool,
    addsContextEntry: Bool = false
  ) throws -> [UInt8] {
    guard HookCommand.isCountersignExecutable(executablePath) else {
      throw HookSetupError.unrecognizableExecutable(executablePath)
    }
    let installed: [UInt8]
    switch host {
    case .claude:
      let permission = try installPermissionEntry(
        into: original, host: host, executablePath: executablePath)
      if addsContextEntry {
        installed = try ContextHookSetup.install(into: permission, executablePath: executablePath)
      } else {
        installed = try ContextHookSetup.refresh(into: permission, executablePath: executablePath)
      }
    case .codex:
      installed = try installPermissionEntry(
        into: original, host: host, executablePath: executablePath)
    case .cursor:
      installed = try CursorHookSetup.install(into: original, executablePath: executablePath)
    case .antigravity:
      installed = try AntigravityHookSetup.install(into: original, executablePath: executablePath)
    }
    guard addsWaitingEntry else {
      return try WaitingHookSetup.refresh(
        into: installed, host: host, executablePath: executablePath)
    }
    return try WaitingHookSetup.install(
      into: installed, host: host, executablePath: executablePath)
  }

  private static func installPermissionEntry(
    into original: [UInt8]?, host: Host, executablePath: String
  ) throws -> [UInt8] {
    let source = original.flatMap { isBlank($0) ? nil : $0 } ?? emptyDocument
    var document = try JSONSourceDocument(bytes: source)
    let group = groupFragment(host: host, executablePath: executablePath)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    guard let hooks = try hooksObject(in: document.root) else {
      let event = JSONFragmentMember(key: eventName, value: .array([group]))
      try document.appendMember(
        JSONFragmentMember(key: "hooks", value: .object([event])), to: document.root)
      return document.bytes
    }
    guard let groups = try eventArray(in: hooks) else {
      try document.appendMember(
        JSONFragmentMember(key: eventName, value: .array([group])), to: hooks)
      return document.bytes
    }
    guard !sites(in: document.root).isEmpty else {
      try document.appendElement(group, to: groups)
      return document.bytes
    }
    try refreshEntries(in: &document, host: host, executablePath: executablePath)
    return document.bytes
  }

  static func refreshEntries(
    in document: inout JSONSourceDocument, host: Host, executablePath: String
  ) throws {
    for index in 0..<hookNodes(in: document.root, host: host).count {
      try updateCommand(ofHook: index, host: host, in: &document, executablePath: executablePath)
      try ensureMember(
        "timeout", ofHook: index, host: host, in: &document, fragment: .integer(timeoutSeconds)
      ) { $0.numberValue == Double(timeoutSeconds) }
      if host == .codex {
        try ensureMember(
          "statusMessage", ofHook: index, host: host, in: &document,
          fragment: .string(codexStatusMessage)
        ) { $0.stringValue == codexStatusMessage }
      }
    }
  }

  public static func uninstall(from original: [UInt8]?, host: Host) throws -> [UInt8]? {
    let withoutPermission: [UInt8]?
    switch host {
    case .claude:
      let removed = try removeEntries(from: original, event: eventName)
      withoutPermission = try ContextHookSetup.uninstall(from: removed)
    case .codex:
      withoutPermission = try removeEntries(from: original, event: eventName)
    case .cursor:
      withoutPermission = try CursorHookSetup.uninstall(from: original)
    case .antigravity:
      withoutPermission = try AntigravityHookSetup.uninstall(from: original)
    }
    return try WaitingHookSetup.uninstall(from: withoutPermission, host: host)
  }

  static func removeEntries(from original: [UInt8]?, event: String) throws -> [UInt8]? {
    guard let original, !isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    guard let hooks = try hooksObject(in: document.root) else { return document.bytes }
    guard try eventArray(in: hooks, event: event) != nil else { return document.bytes }
    while let site = sites(in: document.root, event: event).first {
      if let count = site.groupHooks.elements?.count, count > 1 {
        try document.removeElement(at: site.hookIndex, from: site.groupHooks)
      } else if let count = site.groups.elements?.count, count > 1 {
        try document.removeElement(at: site.groupIndex, from: site.groups)
      } else {
        try document.removeMember(at: site.eventMemberIndex, from: site.hooksObject)
      }
    }
    return document.bytes
  }

  public static func isConfirmation(_ answer: String?) -> Bool {
    guard let answer else { return false }
    let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "y" || normalized == "yes"
  }

  static func hookFragment(host: Host, executablePath: String) -> JSONFragment {
    var members = [
      JSONFragmentMember(key: "type", value: .string("command")),
      JSONFragmentMember(
        key: "command",
        value: .string(HookCommand.command(host: host, executablePath: executablePath))),
      JSONFragmentMember(key: "timeout", value: .integer(timeoutSeconds)),
    ]
    if host == .codex {
      members.append(JSONFragmentMember(key: "statusMessage", value: .string(codexStatusMessage)))
    }
    return .object(members)
  }

  static func groupFragment(host: Host, executablePath: String) -> JSONFragment {
    .object([
      JSONFragmentMember(key: "matcher", value: .string("")),
      JSONFragmentMember(
        key: "hooks", value: .array([hookFragment(host: host, executablePath: executablePath)])),
    ])
  }

  static func sites(in root: JSONSpanNode, event: String = eventName) -> [HookSite] {
    guard let hooksObject = root.member(named: "hooks")?.value,
      let eventMemberIndex = hooksObject.memberIndex(named: event),
      let groups = hooksObject.member(named: event)?.value,
      let groupNodes = groups.elements
    else { return [] }
    var result: [HookSite] = []
    for (groupIndex, group) in groupNodes.enumerated() {
      guard let groupHooks = group.member(named: "hooks")?.value,
        let hookNodes = groupHooks.elements
      else { continue }
      for (hookIndex, hook) in hookNodes.enumerated() where isCountersignHook(hook) {
        result.append(
          HookSite(
            hooksObject: hooksObject, eventMemberIndex: eventMemberIndex, groups: groups,
            groupIndex: groupIndex, groupHooks: groupHooks, hookIndex: hookIndex, hook: hook))
      }
    }
    return result
  }

  static func hookNodes(in root: JSONSpanNode, host: Host) -> [JSONSpanNode] {
    switch host {
    case .claude, .codex: return sites(in: root).map(\.hook)
    case .cursor: return CursorHookSetup.sites(in: root).map(\.hook)
    case .antigravity: return AntigravityHookSetup.hookNodes(in: root)
    }
  }

  static func isCountersignHook(_ hook: JSONSpanNode) -> Bool {
    guard hook.member(named: "type")?.value.stringValue == "command",
      let command = hook.member(named: "command")?.value.stringValue
    else { return false }
    return HookCommand.isCountersignHook(command)
  }

  static func isBlank(_ bytes: [UInt8]) -> Bool {
    bytes.allSatisfy(JSONByte.isWhitespace)
  }

  static func hooksObject(in root: JSONSpanNode) throws -> JSONSpanNode? {
    guard let hooks = root.member(named: "hooks")?.value else { return nil }
    guard hooks.members != nil else {
      throw HookSetupError.unexpectedType(key: "hooks", expected: "an object")
    }
    return hooks
  }

  static func eventArray(in hooks: JSONSpanNode, event: String = eventName) throws
    -> JSONSpanNode?
  {
    guard let node = hooks.member(named: event)?.value else { return nil }
    guard node.elements != nil else {
      throw HookSetupError.unexpectedType(key: "hooks.\(event)", expected: "an array")
    }
    return node
  }

  private static func hookNode(_ index: Int, host: Host, in document: JSONSourceDocument)
    -> JSONSpanNode?
  {
    let all = hookNodes(in: document.root, host: host)
    return all.indices.contains(index) ? all[index] : nil
  }

  private static func updateCommand(
    ofHook index: Int, host: Host, in document: inout JSONSourceDocument, executablePath: String
  ) throws {
    guard
      let command = hookNode(index, host: host, in: document)?.member(named: "command")?.value,
      let text = command.stringValue,
      !HookCommand.isCommand(text, running: executablePath, for: host)
    else { return }
    try document.replaceValue(
      command, with: .string(HookCommand.command(host: host, executablePath: executablePath)))
  }

  private static func ensureMember(
    _ key: String, ofHook index: Int, host: Host, in document: inout JSONSourceDocument,
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
