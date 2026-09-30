import Foundation

public enum WaitingHookSetup {
  static let eventName = "Stop"
  static let timeoutSeconds = 30

  public static let supportedHosts: [Host] = [.claude]

  public static func install(into original: [UInt8]?, host: Host, executablePath: String) throws
    -> [UInt8]
  {
    guard supportedHosts.contains(host) else { return original ?? [] }
    guard HookCommand.isCountersignExecutable(executablePath) else {
      throw HookSetupError.unrecognizableExecutable(executablePath)
    }
    let source = original.flatMap { HookSetup.isBlank($0) ? nil : $0 } ?? HookSetup.emptyDocument
    var document = try JSONSourceDocument(bytes: source)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    let group = groupFragment(host: host, executablePath: executablePath)
    guard let hooks = try HookSetup.hooksObject(in: document.root) else {
      let event = JSONFragmentMember(key: eventName, value: .array([group]))
      try document.appendMember(
        JSONFragmentMember(key: "hooks", value: .object([event])), to: document.root)
      return document.bytes
    }
    guard let groups = try HookSetup.eventArray(in: hooks, event: eventName) else {
      try document.appendMember(
        JSONFragmentMember(key: eventName, value: .array([group])), to: hooks)
      return document.bytes
    }
    guard !HookSetup.sites(in: document.root, event: eventName).isEmpty else {
      try document.appendElement(group, to: groups)
      return document.bytes
    }
    try refreshEntries(in: &document, host: host, executablePath: executablePath)
    return document.bytes
  }

  public static func refresh(into original: [UInt8], host: Host, executablePath: String) throws
    -> [UInt8]
  {
    guard supportedHosts.contains(host), !HookSetup.isBlank(original) else { return original }
    var document = try JSONSourceDocument(bytes: original)
    try refreshEntries(in: &document, host: host, executablePath: executablePath)
    return document.bytes
  }

  public static func uninstall(from original: [UInt8]?, host: Host) throws -> [UInt8]? {
    guard supportedHosts.contains(host) else { return original }
    return try HookSetup.removeEntries(from: original, event: eventName)
  }

  public static func entries(in bytes: [UInt8], host: Host) -> [ContextHookEntry] {
    guard supportedHosts.contains(host), let root = try? JSONSpanReader.parse(bytes) else {
      return []
    }
    return HookSetup.sites(in: root, event: eventName).map { site in
      ContextHookEntry(
        command: site.hook.member(named: "command")?.value.stringValue ?? "",
        isAsync: ContextHookSetup.isAsync(site.hook),
        timeoutSeconds: site.hook.member(named: "timeout")?.value.numberValue)
    }
  }

  private static func hookFragment(host: Host, executablePath: String) -> JSONFragment {
    .object([
      JSONFragmentMember(key: "type", value: .string("command")),
      JSONFragmentMember(
        key: "command",
        value: .string(
          HookCommand.command(host: host, executablePath: executablePath, event: .waiting))),
      JSONFragmentMember(key: "async", value: .bool(true)),
      JSONFragmentMember(key: "timeout", value: .integer(timeoutSeconds)),
    ])
  }

  private static func groupFragment(host: Host, executablePath: String) -> JSONFragment {
    .object([
      JSONFragmentMember(
        key: "hooks",
        value: .array([hookFragment(host: host, executablePath: executablePath)]))
    ])
  }

  private static func refreshEntries(
    in document: inout JSONSourceDocument, host: Host, executablePath: String
  ) throws {
    for index in 0..<HookSetup.sites(in: document.root, event: eventName).count {
      try updateCommand(ofHook: index, in: &document, host: host, executablePath: executablePath)
      try ensureMember("async", ofHook: index, in: &document, fragment: .bool(true)) {
        $0.content == .bool(true)
      }
      try ensureMember(
        "timeout", ofHook: index, in: &document, fragment: .integer(timeoutSeconds)
      ) { $0.numberValue == Double(timeoutSeconds) }
    }
  }

  private static func hookNode(_ index: Int, in document: JSONSourceDocument) -> JSONSpanNode? {
    let all = HookSetup.sites(in: document.root, event: eventName).map(\.hook)
    return all.indices.contains(index) ? all[index] : nil
  }

  private static func updateCommand(
    ofHook index: Int, in document: inout JSONSourceDocument, host: Host, executablePath: String
  ) throws {
    guard let command = hookNode(index, in: document)?.member(named: "command")?.value,
      let text = command.stringValue,
      !HookCommand.isCommand(text, running: executablePath, for: host, event: .waiting)
    else { return }
    try document.replaceValue(
      command,
      with: .string(
        HookCommand.command(host: host, executablePath: executablePath, event: .waiting)))
  }

  private static func ensureMember(
    _ key: String, ofHook index: Int, in document: inout JSONSourceDocument,
    fragment: JSONFragment, matches: (JSONSpanNode) -> Bool
  ) throws {
    guard let hook = hookNode(index, in: document) else { return }
    guard let existing = hook.member(named: key) else {
      try document.appendMember(JSONFragmentMember(key: key, value: fragment), to: hook)
      return
    }
    guard !matches(existing.value) else { return }
    try document.replaceValue(existing.value, with: fragment)
  }
}
