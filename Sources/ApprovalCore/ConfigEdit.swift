import Foundation

public enum PreferenceName: String, Sendable, Equatable, Hashable, CaseIterable {
  case armDelay
  case chainedArmDelay
  case idleSeconds
  case graceSeconds
  case snoozeMinutes
  case handoffApps
  case checkForUpdates
  case questionNotes
  case quitBehavior
  case modeAfterPlan
  case appearance
  case accentColor
  case editorApp
}

public enum PreferenceEdit: Sendable, Equatable {
  case armDelay(Double)
  case chainedArmDelay(Double)
  case idleSeconds(Double)
  case graceSeconds(Double)
  case snoozeMinutes([Int])
  case checkForUpdates(Bool)
  case quitBehavior(QuitBehavior)
  case modeAfterPlan(PlanApprovalMode)
  case questionNotes(Bool)
  case appearance(AppearanceChoice)
  case accentColor(HexColor)
  case addHandoffApp(String)
  case removeHandoffApp(String)
  case editorApp(String)
  case reset(PreferenceName)

  public var key: PreferenceName {
    switch self {
    case .armDelay: return .armDelay
    case .chainedArmDelay: return .chainedArmDelay
    case .idleSeconds: return .idleSeconds
    case .graceSeconds: return .graceSeconds
    case .snoozeMinutes: return .snoozeMinutes
    case .checkForUpdates: return .checkForUpdates
    case .quitBehavior: return .quitBehavior
    case .modeAfterPlan: return .modeAfterPlan
    case .questionNotes: return .questionNotes
    case .appearance: return .appearance
    case .accentColor: return .accentColor
    case .addHandoffApp, .removeHandoffApp: return .handoffApps
    case .editorApp: return .editorApp
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
    let key = edit.key.rawValue
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
    case .reset:
      try removeTopLevelMember(key, in: &document)
    }
  }

  private static func removeTopLevelMember(_ key: String, in document: inout JSONSourceDocument)
    throws
  {
    guard let index = document.root.memberIndex(named: key) else { return }
    try document.removeMember(at: index, from: document.root)
  }

  private static func set(
    _ key: String, to fragment: JSONFragment, in document: inout JSONSourceDocument,
    holds: (JSONSpanNode) -> Bool
  ) throws {
    guard let existing = document.root.member(named: key) else {
      try document.appendMember(JSONFragmentMember(key: key, value: fragment), to: document.root)
      return
    }
    guard !holds(existing.value) else { return }
    try document.replaceValue(existing.value, with: fragment)
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
