import Foundation

public struct ContextHookEntry: Sendable, Equatable {
  public var event: String
  public var command: String
  public var isAsync: Bool
  public var timeoutSeconds: Double?

  public init(event: String, command: String, isAsync: Bool, timeoutSeconds: Double?) {
    self.event = event
    self.command = command
    self.isAsync = isAsync
    self.timeoutSeconds = timeoutSeconds
  }
}

public enum ContextHookSetup {
  public static let eventName = "UserPromptSubmit"
  public static let toolEventName = "PostToolUse"
  public static let eventNames = [eventName, toolEventName]
  public static let timeoutSeconds = HookSetup.timeoutSeconds

  public static func install(into original: [UInt8]?, executablePath: String) throws -> [UInt8] {
    guard HookCommand.isCountersignExecutable(executablePath) else {
      throw HookSetupError.unrecognizableExecutable(executablePath)
    }
    let source = original.flatMap { HookSetup.isBlank($0) ? nil : $0 } ?? HookSetup.emptyDocument
    var document = try JSONSourceDocument(bytes: source)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    for event in eventNames {
      try install(event: event, into: &document, executablePath: executablePath)
    }
    return document.bytes
  }

  private static func install(
    event: String, into document: inout JSONSourceDocument, executablePath: String
  ) throws {
    let group = groupFragment(executablePath: executablePath)
    guard let hooks = try HookSetup.hooksObject(in: document.root) else {
      let member = JSONFragmentMember(key: event, value: .array([group]))
      try document.appendMember(
        JSONFragmentMember(key: "hooks", value: .object([member])), to: document.root)
      return
    }
    guard let groups = try HookSetup.eventArray(in: hooks, event: event) else {
      try document.appendMember(JSONFragmentMember(key: event, value: .array([group])), to: hooks)
      return
    }
    guard !HookSetup.sites(in: document.root, event: event).isEmpty else {
      try document.appendElement(group, to: groups)
      return
    }
    try refreshEntries(event: event, in: &document, executablePath: executablePath)
  }

  public static func refresh(into original: [UInt8], executablePath: String) throws -> [UInt8] {
    guard !HookSetup.isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    for event in eventNames {
      try refreshEntries(event: event, in: &document, executablePath: executablePath)
    }
    return document.bytes
  }

  public static func uninstall(from original: [UInt8]?) throws -> [UInt8]? {
    try eventNames.reduce(original) { try HookSetup.removeEntries(from: $0, event: $1) }
  }

  public static func entries(in bytes: [UInt8]) -> [ContextHookEntry] {
    guard let root = try? JSONSpanReader.parse(bytes) else { return [] }
    return eventNames.flatMap { event in
      HookSetup.sites(in: root, event: event).map { site in
        ContextHookEntry(
          event: event,
          command: site.hook.member(named: "command")?.value.stringValue ?? "",
          isAsync: isAsync(site.hook),
          timeoutSeconds: site.hook.member(named: "timeout")?.value.numberValue)
      }
    }
  }

  static func isAsync(_ hook: JSONSpanNode) -> Bool {
    hook.member(named: "async")?.value.content == .bool(true)
  }

  static func hookFragment(executablePath: String) -> JSONFragment {
    .object([
      JSONFragmentMember(key: "type", value: .string("command")),
      JSONFragmentMember(
        key: "command",
        value: .string(HookCommand.command(host: .claude, executablePath: executablePath))),
      JSONFragmentMember(key: "async", value: .bool(true)),
      JSONFragmentMember(key: "timeout", value: .integer(timeoutSeconds)),
    ])
  }

  static func groupFragment(executablePath: String) -> JSONFragment {
    .object([
      JSONFragmentMember(
        key: "hooks", value: .array([hookFragment(executablePath: executablePath)]))
    ])
  }

  private static func refreshEntries(
    event: String, in document: inout JSONSourceDocument, executablePath: String
  ) throws {
    for index in 0..<HookSetup.sites(in: document.root, event: event).count {
      try updateCommand(ofHook: index, event: event, in: &document, executablePath: executablePath)
      try ensureMember("async", ofHook: index, event: event, in: &document, fragment: .bool(true)) {
        $0.content == .bool(true)
      }
      try ensureMember(
        "timeout", ofHook: index, event: event, in: &document, fragment: .integer(timeoutSeconds)
      ) { $0.numberValue == Double(timeoutSeconds) }
    }
  }

  private static func hookNode(_ index: Int, event: String, in document: JSONSourceDocument)
    -> JSONSpanNode?
  {
    let all = HookSetup.sites(in: document.root, event: event).map(\.hook)
    return all.indices.contains(index) ? all[index] : nil
  }

  private static func updateCommand(
    ofHook index: Int, event: String, in document: inout JSONSourceDocument, executablePath: String
  ) throws {
    guard
      let command = hookNode(index, event: event, in: document)?.member(named: "command")?.value,
      let text = command.stringValue,
      !HookCommand.isCommand(text, running: executablePath, for: .claude)
    else { return }
    try document.replaceValue(
      command, with: .string(HookCommand.command(host: .claude, executablePath: executablePath)))
  }

  private static func ensureMember(
    _ key: String, ofHook index: Int, event: String, in document: inout JSONSourceDocument,
    fragment: JSONFragment, matches: (JSONSpanNode) -> Bool
  ) throws {
    guard let hook = hookNode(index, event: event, in: document) else { return }
    guard let existing = hook.member(named: key) else {
      try document.appendMember(JSONFragmentMember(key: key, value: fragment), to: hook)
      return
    }
    guard !matches(existing.value) else { return }
    try document.replaceValue(existing.value, with: fragment)
  }
}
