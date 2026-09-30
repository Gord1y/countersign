import Foundation

public enum PreferenceName: String, Sendable, Equatable, Hashable, CaseIterable {
  case armDelay
  case chainedArmDelay
  case idleSeconds
  case graceSeconds
  case snoozeMinutes
  case quietHours
  case handoffApps
  case checkForUpdates
  case questionNotes
  case quitBehavior
  case modeAfterPlan
  case appearance
  case accentColor
  case editorApp
  case panelSound
  case waitingNotices
  case waitingNoticeMinutes
  case contextCheckpointsEnabled
  case contextMode
  case contextStandardThresholds
  case contextMillionThresholds
  case contextModelThresholds
  case contextRearmBelow
  case contextHandoffFile
  case contextNoteSoft
  case contextNoteStatus
  case contextNoteInsist
  case contextNoteCompact
  case contextNoteHandoff
  case contextMenuBarMeter

  public var keyPath: [String] {
    switch self {
    case .contextCheckpointsEnabled: return ["contextCheckpoints", "enabled"]
    case .contextMode: return ["contextCheckpoints", "mode"]
    case .contextStandardThresholds: return ["contextCheckpoints", "thresholds", "200k"]
    case .contextMillionThresholds: return ["contextCheckpoints", "thresholds", "1m"]
    case .contextModelThresholds: return ["contextCheckpoints", "modelThresholds"]
    case .contextRearmBelow: return ["contextCheckpoints", "rearmBelow"]
    case .contextHandoffFile: return ["contextCheckpoints", "handoffFile"]
    case .contextNoteSoft: return ["contextCheckpoints", "notes", "soft"]
    case .contextNoteStatus: return ["contextCheckpoints", "notes", "status"]
    case .contextNoteInsist: return ["contextCheckpoints", "notes", "insist"]
    case .contextNoteCompact: return ["contextCheckpoints", "notes", "compact"]
    case .contextNoteHandoff: return ["contextCheckpoints", "notes", "handoff"]
    case .contextMenuBarMeter: return ["contextCheckpoints", "menuBarMeter"]
    default: return [rawValue]
    }
  }

  public var noteName: String? {
    switch self {
    case .contextNoteSoft, .contextNoteStatus, .contextNoteInsist, .contextNoteCompact,
      .contextNoteHandoff:
      return keyPath.last
    default:
      return nil
    }
  }
}

public enum PreferenceEdit: Sendable, Equatable {
  case armDelay(Double)
  case chainedArmDelay(Double)
  case idleSeconds(Double)
  case graceSeconds(Double)
  case snoozeMinutes([Int])
  case quietHours([QuietWindow])
  case checkForUpdates(Bool)
  case quitBehavior(QuitBehavior)
  case modeAfterPlan(PlanApprovalMode)
  case panelSound(String)
  case waitingNotices(Bool)
  case waitingNoticeMinutes(Int)
  case questionNotes(Bool)
  case appearance(AppearanceChoice)
  case accentColor(HexColor)
  case addHandoffApp(String)
  case removeHandoffApp(String)
  case editorApp(String)
  case contextCheckpointsEnabled(Bool)
  case contextMode(ContextCheckpointMode)
  case contextStandardThresholds([Int])
  case contextMillionThresholds([Int])
  case setContextModelThresholds(prefix: String, ladder: [Int])
  case removeContextModelThresholds(prefix: String)
  case contextRearmBelow(Double)
  case contextHandoffFile(String)
  case contextNote(PreferenceName, String)
  case contextMenuBarMeter(Bool)
  case reset(PreferenceName)

  public var key: PreferenceName {
    switch self {
    case .armDelay: return .armDelay
    case .chainedArmDelay: return .chainedArmDelay
    case .idleSeconds: return .idleSeconds
    case .graceSeconds: return .graceSeconds
    case .snoozeMinutes: return .snoozeMinutes
    case .quietHours: return .quietHours
    case .checkForUpdates: return .checkForUpdates
    case .quitBehavior: return .quitBehavior
    case .modeAfterPlan: return .modeAfterPlan
    case .panelSound: return .panelSound
    case .waitingNotices: return .waitingNotices
    case .waitingNoticeMinutes: return .waitingNoticeMinutes
    case .questionNotes: return .questionNotes
    case .appearance: return .appearance
    case .accentColor: return .accentColor
    case .addHandoffApp, .removeHandoffApp: return .handoffApps
    case .editorApp: return .editorApp
    case .contextCheckpointsEnabled: return .contextCheckpointsEnabled
    case .contextMode: return .contextMode
    case .contextStandardThresholds: return .contextStandardThresholds
    case .contextMillionThresholds: return .contextMillionThresholds
    case .setContextModelThresholds, .removeContextModelThresholds:
      return .contextModelThresholds
    case .contextRearmBelow: return .contextRearmBelow
    case .contextHandoffFile: return .contextHandoffFile
    case .contextNote(let name, _): return name
    case .contextMenuBarMeter: return .contextMenuBarMeter
    case .reset(let name): return name
    }
  }
}

public enum ConfigEdit {
  public static func applying(_ edits: [PreferenceEdit], to original: [UInt8]?) throws
    -> [UInt8]
  {
    let source =
      original.flatMap { HookSetup.isBlank($0) ? nil : $0 }
      ?? Array(ConfigFileStarter.contents.utf8)
    var document = try JSONSourceDocument(bytes: source)
    guard case .object = document.root.content else {
      throw HookSetupError.unexpectedType(key: "the top level", expected: "an object")
    }
    for edit in edits {
      try apply(edit, to: &document)
    }
    return document.bytes
  }

  public static func problem(in original: [UInt8]?) -> String? {
    do {
      _ = try applying([], to: original)
      return nil
    } catch {
      return SetupRun.describe(error)
    }
  }

  static func spelling(_ value: Double) -> String {
    PreferenceRules.numberText(value)
  }

  private static func apply(_ edit: PreferenceEdit, to document: inout JSONSourceDocument)
    throws
  {
    let path = edit.key.keyPath
    let key = path.first ?? edit.key.rawValue
    switch edit {
    case .armDelay(let value), .chainedArmDelay(let value), .idleSeconds(let value),
      .graceSeconds(let value):
      try set(key, to: .number(spelling(value)), in: &document) {
        $0.numberValue == value
      }
    case .snoozeMinutes(let minutes):
      try set(key, to: .array(minutes.map(JSONFragment.integer)), in: &document) {
        $0.elements?.map(\.numberValue) == minutes.map { Double($0) }
      }
    case .quietHours(let windows):
      try set(key, to: .array(windows.map(quietWindowFragment)), in: &document) { _ in false }
    case .checkForUpdates(let enabled):
      try set(key, to: .bool(enabled), in: &document) { $0.content == .bool(enabled) }
    case .quitBehavior(let behavior):
      try set(key, to: .string(behavior.rawValue), in: &document) {
        $0.stringValue == behavior.rawValue
      }
    case .modeAfterPlan(let mode):
      try set(key, to: .string(mode.rawValue), in: &document) {
        $0.stringValue == mode.rawValue
      }
    case .panelSound(let name):
      try set(key, to: .string(name), in: &document) { $0.stringValue == name }
    case .waitingNotices(let enabled):
      try set(key, to: .bool(enabled), in: &document) { $0.content == .bool(enabled) }
    case .waitingNoticeMinutes(let minutes):
      try set(key, to: .integer(minutes), in: &document) { $0.numberValue == Double(minutes) }
    case .questionNotes(let enabled):
      try set(key, to: .bool(enabled), in: &document) { $0.content == .bool(enabled) }
    case .appearance(let appearance):
      try set(key, to: .string(appearance.rawValue), in: &document) {
        $0.stringValue == appearance.rawValue
      }
    case .accentColor(let color):
      try set(key, to: .string(color.hex), in: &document) {
        $0.stringValue.flatMap(HexColor.init(hex:)) == color
      }
    case .addHandoffApp(let bundleID):
      try add(bundleID, key: key, in: &document)
    case .removeHandoffApp(let bundleID):
      try remove(bundleID, key: key, in: &document)
    case .editorApp(let bundleID):
      try set(key, to: .string(bundleID), in: &document) { $0.stringValue == bundleID }
    case .contextCheckpointsEnabled(let enabled), .contextMenuBarMeter(let enabled):
      try set(path, to: .bool(enabled), in: &document) { $0.content == .bool(enabled) }
    case .contextMode(let mode):
      try set(path, to: .string(mode.rawValue), in: &document) {
        $0.stringValue == mode.rawValue
      }
    case .contextStandardThresholds(let ladder), .contextMillionThresholds(let ladder):
      try set(path, to: .array(ladder.map(JSONFragment.integer)), in: &document) {
        $0.elements?.map(\.numberValue) == ladder.map { Double($0) }
      }
    case .setContextModelThresholds(let prefix, let ladder):
      try set(path + [prefix], to: .array(ladder.map(JSONFragment.integer)), in: &document) {
        $0.elements?.map(\.numberValue) == ladder.map { Double($0) }
      }
    case .removeContextModelThresholds(let prefix):
      try removeMember(path + [prefix], in: &document)
    case .contextRearmBelow(let ratio):
      try set(path, to: .number(spelling(ratio)), in: &document) { $0.numberValue == ratio }
    case .contextHandoffFile(let file):
      try set(path, to: .string(file), in: &document) { $0.stringValue == file }
    case .contextNote(let name, let text):
      guard name.noteName != nil else { return }
      try set(path, to: .string(text), in: &document) { $0.stringValue == text }
    case .reset:
      try removeMember(path, in: &document)
    }
  }

  private static func quietWindowFragment(_ window: QuietWindow) -> JSONFragment {
    .object([
      JSONFragmentMember(key: "days", value: .array(window.days.map { .string($0.rawValue) })),
      JSONFragmentMember(key: "from", value: .string(window.fromText)),
      JSONFragmentMember(key: "to", value: .string(window.toText)),
    ])
  }

  private static func removeMember(_ path: [String], in document: inout JSONSourceDocument)
    throws
  {
    var parent = document.root
    for key in path.dropLast() {
      guard let child = parent.member(named: key)?.value, child.members != nil else { return }
      parent = child
    }
    guard let leaf = path.last, let index = parent.memberIndex(named: leaf) else { return }
    try document.removeMember(at: index, from: parent)
  }

  private static func set(
    _ key: String, to fragment: JSONFragment, in document: inout JSONSourceDocument,
    holds: (JSONSpanNode) -> Bool
  ) throws {
    try set([key], to: fragment, in: &document, holds: holds)
  }

  private static func set(
    _ path: [String], to fragment: JSONFragment, in document: inout JSONSourceDocument,
    holds: (JSONSpanNode) -> Bool
  ) throws {
    var parent = document.root
    for (depth, key) in path.dropLast().enumerated() {
      guard let existing = parent.member(named: key) else {
        let missing = nested(Array(path.dropFirst(depth + 1)), around: fragment)
        try document.appendMember(JSONFragmentMember(key: key, value: missing), to: parent)
        return
      }
      guard existing.value.members != nil else {
        let replacement = nested(Array(path.dropFirst(depth + 1)), around: fragment)
        try document.replaceValue(existing.value, with: replacement)
        return
      }
      parent = existing.value
    }
    guard let leaf = path.last else { return }
    guard let existing = parent.member(named: leaf) else {
      try document.appendMember(JSONFragmentMember(key: leaf, value: fragment), to: parent)
      return
    }
    guard !holds(existing.value) else { return }
    try document.replaceValue(existing.value, with: fragment)
  }

  private static func nested(_ path: [String], around fragment: JSONFragment) -> JSONFragment {
    path.reversed().reduce(fragment) { inner, key in
      .object([JSONFragmentMember(key: key, value: inner)])
    }
  }

  private static func add(_ bundleID: String, key: String, in document: inout JSONSourceDocument)
    throws
  {
    let fresh = JSONFragment.array([.string(bundleID)])
    guard let existing = document.root.member(named: key)?.value else {
      try document.appendMember(JSONFragmentMember(key: key, value: fresh), to: document.root)
      return
    }
    guard let elements = existing.elements, elements.allSatisfy({ $0.stringValue != nil }) else {
      try document.replaceValue(existing, with: fresh)
      return
    }
    guard !elements.contains(where: { $0.stringValue == bundleID }) else { return }
    try document.appendElement(.string(bundleID), to: existing)
  }

  private static func remove(
    _ bundleID: String, key: String, in document: inout JSONSourceDocument
  ) throws {
    while let array = document.root.member(named: key)?.value,
      let index = array.elements?.firstIndex(where: { $0.stringValue == bundleID })
    {
      try document.removeElement(at: index, from: array)
    }
  }
}
