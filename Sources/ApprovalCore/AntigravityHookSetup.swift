import Foundation

enum AntigravityHookSetup {
  static let hookName = "countersign"
  static let matcher = "*"
  static let entryKeys: Set<String> = ["type", "command", "timeout"]

  static func install(into original: [UInt8]?, executablePath: String) throws -> [UInt8] {
    let source = original.flatMap { HookSetup.isBlank($0) ? nil : $0 } ?? HookSetup.emptyDocument
    var document = try JSONSourceDocument(bytes: source)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    let namedHook = namedHookFragment(executablePath: executablePath)
    guard let ours = document.root.member(named: hookName)?.value else {
      try document.appendMember(
        JSONFragmentMember(key: hookName, value: namedHook), to: document.root)
      return document.bytes
    }
    guard entry(inSetupShape: ours) != nil else {
      try document.replaceValue(ours, with: namedHook)
      return document.bytes
    }
    try HookSetup.refreshEntries(in: &document, host: .antigravity, executablePath: executablePath)
    return document.bytes
  }

  static func uninstall(from original: [UInt8]?) throws -> [UInt8]? {
    guard let original, !HookSetup.isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    while let index = document.root.memberIndex(named: hookName) {
      try document.removeMember(at: index, from: document.root)
    }
    return document.bytes
  }

  static func hookNodes(in root: JSONSpanNode) -> [JSONSpanNode] {
    guard let ours = root.member(named: hookName)?.value, let hook = entry(inSetupShape: ours)
    else { return [] }
    return [hook]
  }

  static func hasNamedHook(in root: JSONSpanNode) -> Bool {
    root.member(named: hookName) != nil
  }

  static func entry(inSetupShape namedHook: JSONSpanNode) -> JSONSpanNode? {
    guard let events = namedHook.members, events.count == 1,
      events[0].key == AntigravityAdapter.event,
      let groups = events[0].value.elements, groups.count == 1,
      let groupMembers = groups[0].members, groupMembers.count == 2,
      groups[0].member(named: "matcher")?.value.stringValue == matcher,
      let hooks = groups[0].member(named: "hooks")?.value.elements
    else { return nil }
    return onlyCountersignHandler(in: hooks)
  }

  static func flatEntry(inSetupShape namedHook: JSONSpanNode, event: String) -> JSONSpanNode? {
    guard let events = namedHook.members, events.count == 1,
      events[0].key == event,
      let handlers = events[0].value.elements
    else { return nil }
    return onlyCountersignHandler(in: handlers)
  }

  private static func onlyCountersignHandler(in handlers: [JSONSpanNode]) -> JSONSpanNode? {
    guard handlers.count == 1,
      let handlerMembers = handlers[0].members,
      Set(handlerMembers.map(\.key)).count == handlerMembers.count,
      Set(handlerMembers.map(\.key)).isSubset(of: entryKeys),
      HookSetup.isCountersignHook(handlers[0])
    else { return nil }
    return handlers[0]
  }

  static func namedHookFragment(executablePath: String) -> JSONFragment {
    let group = JSONFragment.object([
      JSONFragmentMember(key: "matcher", value: .string(matcher)),
      JSONFragmentMember(
        key: "hooks",
        value: .array([HookSetup.hookFragment(host: .antigravity, executablePath: executablePath)])),
    ])
    return .object([JSONFragmentMember(key: AntigravityAdapter.event, value: .array([group]))])
  }
}
