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

  public static func install(into original: [UInt8]?, host: Host, executablePath: String) throws
    -> [UInt8]
  {
    guard HookCommand.isCountersignExecutable(executablePath) else {
      throw HookSetupError.unrecognizableExecutable(executablePath)
    }
    switch host {
    case .claude, .codex:
      break
    case .cursor:
      return try CursorHookSetup.install(into: original, executablePath: executablePath)
    case .antigravity:
      return try AntigravityHookSetup.install(into: original, executablePath: executablePath)
    }
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
    switch host {
    case .claude, .codex:
      break
    case .cursor:
      return try CursorHookSetup.uninstall(from: original)
    case .antigravity:
      return try AntigravityHookSetup.uninstall(from: original)
    }
    guard let original, !isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    guard let hooks = try hooksObject(in: document.root) else { return document.bytes }
    guard try eventArray(in: hooks) != nil else { return document.bytes }
    while let site = sites(in: document.root).first {
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

  static func sites(in root: JSONSpanNode) -> [HookSite] {
    guard let hooksObject = root.member(named: "hooks")?.value,
      let eventMemberIndex = hooksObject.memberIndex(named: eventName),
      let groups = hooksObject.member(named: eventName)?.value,
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

  private static func hooksObject(in root: JSONSpanNode) throws -> JSONSpanNode? {
    guard let hooks = root.member(named: "hooks")?.value else { return nil }
    guard hooks.members != nil else {
      throw HookSetupError.unexpectedType(key: "hooks", expected: "an object")
    }
    return hooks
  }

  private static func eventArray(in hooks: JSONSpanNode) throws -> JSONSpanNode? {
    guard let event = hooks.member(named: eventName)?.value else { return nil }
    guard event.elements != nil else {
      throw HookSetupError.unexpectedType(key: "hooks.\(eventName)", expected: "an array")
    }
    return event
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
