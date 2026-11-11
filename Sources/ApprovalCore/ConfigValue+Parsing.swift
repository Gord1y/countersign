import Foundation

extension ConfigValue {
  static func invalid<Reason: CustomStringConvertible>(_ reason: Reason) -> ConfigValueError {
    .invalid(reason.description)
  }

  static func boolean(_ text: String) -> Result<Bool, ConfigValueError> {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "true", "on": return .success(true)
    case "false", "off": return .success(false)
    default: return .failure(.invalid("expected true, false, on or off"))
    }
  }

  static func duration(_ name: PreferenceName, _ text: String)
    -> Result<TimeInterval, ConfigValueError>
  {
    guard let spec = name.durationField else {
      return .failure(.invalid("\(name.commandLineKey) is not a duration"))
    }
    return PreferenceRules.duration(from: text, spec: spec).mapError(invalid)
  }

  static func words(_ names: [String]) -> String {
    guard let last = names.last, names.count > 1 else { return names.first ?? "" }
    return "\(names.dropLast().joined(separator: ", ")) or \(last)"
  }

  static func rawValue<Value: RawRepresentable & CaseIterable>(
    _ text: String, as type: Value.Type
  ) -> Result<Value, ConfigValueError> where Value.RawValue == String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard let value = Value.allCases.first(where: { $0.rawValue == trimmed }) else {
      return .failure(.invalid("expected \(words(Value.allCases.map(\.rawValue)))"))
    }
    return .success(value)
  }

  static func entries(_ text: String, separator: Character) -> [String] {
    text.split(separator: separator, omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  static func isNone(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "none"
  }

  static func quietWindows(_ text: String) -> Result<[QuietWindow], ConfigValueError> {
    guard !isNone(text) else { return .success([]) }
    var windows: [QuietWindow] = []
    for entry in entries(text, separator: ";") {
      switch quietWindow(entry, joining: windows) {
      case .success(let window): windows.append(window)
      case .failure(let error): return .failure(error)
      }
    }
    return .success(windows)
  }

  private static let quietWindowShape = "expected <days> <from>-<to>, like mon,tue 22:00-07:00"

  private static func quietWindow(_ entry: String, joining existing: [QuietWindow])
    -> Result<QuietWindow, ConfigValueError>
  {
    let tokens = entry.split(whereSeparator: \.isWhitespace)
    guard tokens.count >= 2, let range = tokens.last else {
      return .failure(.invalid(quietWindowShape))
    }
    let times = range.split(separator: "-", omittingEmptySubsequences: false)
    guard times.count == 2 else { return .failure(.invalid(quietWindowShape)) }
    let dayNames = tokens.dropLast().joined(separator: ",").split(separator: ",").map(String.init)
    var days: [QuietWeekday] = []
    for dayName in dayNames {
      guard let day = QuietWeekday(rawValue: dayName.lowercased()) else {
        return .failure(
          .invalid(
            "\"\(dayName)\" is not a day; use \(words(QuietWeekday.allCases.map(\.rawValue)))"))
      }
      days.append(day)
    }
    return PreferenceRules.quietWindow(
      days: days, from: String(times[0]), to: String(times[1]), joining: existing
    ).mapError(invalid)
  }

  static func handoffAppList(_ text: String) -> Result<[String], ConfigValueError> {
    guard !isNone(text) else { return .success([]) }
    var apps: [String] = []
    for entry in entries(text, separator: ",") {
      switch PreferenceRules.handoffApp(entry, joining: apps) {
      case .success(let app): apps.append(app)
      case .failure(let error): return .failure(invalid(error))
      }
    }
    return .success(apps)
  }

  static func handoffEdits(listed: [String], current: [String]) -> [PreferenceEdit] {
    let removals: [PreferenceEdit] = current.filter { !listed.contains($0) }.map {
      PreferenceEdit.removeHandoffApp($0)
    }
    let additions: [PreferenceEdit] = listed.filter { !current.contains($0) }.map {
      PreferenceEdit.addHandoffApp($0)
    }
    return removals + additions
  }

  static func approvalCardHosts(_ text: String) -> Result<[Host], ConfigValueError> {
    switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "on": return .success(Host.allCases)
    case "off", "none": return .success([])
    default: break
    }
    var hosts: [Host] = []
    for entry in entries(text, separator: ",") {
      guard let host = Host(rawValue: entry) else {
        return .failure(
          .invalid(
            "\"\(entry)\" is not an agent; use on, off or \(words(Host.allCases.map(\.rawValue)))"
          ))
      }
      hosts.append(host)
    }
    return .success(hosts)
  }

  static func panelSound(_ text: String) -> Result<String, ConfigValueError> {
    let name = text.trimmingCharacters(in: .whitespaces)
    guard PanelSound.isSilent(name) || PanelSound.systemNames.contains(name) else {
      return .failure(
        .invalid("expected \"\(PanelSound.none)\" or the name of a system sound"))
    }
    return .success(name)
  }

  static func accentColor(_ text: String) -> Result<HexColor, ConfigValueError> {
    guard let color = HexColor(hex: text.trimmingCharacters(in: .whitespaces)) else {
      return .failure(.invalid("expected a colour like #3B82F6"))
    }
    return .success(color)
  }

  static func batteryCutoff(_ text: String) -> Result<Int, ConfigValueError> {
    let range = Settings.keepAwakeBatteryCutoffRange
    let step = Settings.keepAwakeBatteryCutoffStep
    guard let percent = PreferenceRules.batteryCutoff(from: text) else {
      return .failure(
        .invalid("expected \(range.lowerBound) to \(range.upperBound) in steps of \(step)"))
    }
    return .success(percent)
  }

  static func editorApp(_ text: String) -> Result<[PreferenceEdit], ConfigValueError> {
    guard !isNone(text) else { return .success([.reset(.editorApp)]) }
    return PreferenceRules.handoffApp(text, joining: []).mapError(invalid).map {
      [.editorApp($0)]
    }
  }

  static func modelThresholdList(_ text: String) -> Result<[String: [Int]], ConfigValueError> {
    guard !isNone(text) else { return .success([:]) }
    var listed: [String: [Int]] = [:]
    for entry in entries(text, separator: ";") {
      let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else {
        return .failure(.invalid("expected <prefix>=<ladder>, like claude-opus-5=200,400"))
      }
      switch PreferenceRules.contextModelPrefix(String(parts[0])).mapError(invalid) {
      case .failure(let error): return .failure(error)
      case .success(let prefix):
        switch PreferenceRules.contextLadder(fromThousands: String(parts[1])).mapError(invalid) {
        case .failure(let error): return .failure(error)
        case .success(let ladder):
          guard listed[prefix] == nil else {
            return .failure(.invalid("\"\(prefix)\" is listed twice"))
          }
          listed[prefix] = ladder
        }
      }
    }
    return .success(listed)
  }

  static func modelThresholdEdits(listed: [String: [Int]], current: [String: [Int]])
    -> [PreferenceEdit]
  {
    let removals: [PreferenceEdit] = current.keys.sorted().filter { listed[$0] == nil }.map {
      PreferenceEdit.removeContextModelThresholds(prefix: $0)
    }
    let additions: [PreferenceEdit] = listed.keys.sorted().compactMap { prefix in
      listed[prefix].map { PreferenceEdit.setContextModelThresholds(prefix: prefix, ladder: $0) }
    }
    return removals + additions
  }

  static func rearmPercent(_ text: String) -> Result<Double, ConfigValueError> {
    var trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("%") { trimmed.removeLast() }
    let range = PreferenceRules.contextRearmPercentRange
    let step = PreferenceRules.contextRearmPercentStep
    guard let percent = Double(trimmed.trimmingCharacters(in: .whitespaces)),
      range.contains(percent), percent.truncatingRemainder(dividingBy: step) == 0
    else {
      return .failure(
        .invalid(
          "expected \(Int(range.lowerBound)) to \(Int(range.upperBound)) percent"
            + " in steps of \(Int(step))"))
    }
    return .success(PreferenceRules.contextRearmBelow(percent: percent))
  }

  static func maxCompactions(_ text: String) -> Result<Int, ConfigValueError> {
    let range = ContextCheckpointSettings.maxCompactionsRange
    guard let count = Int(text.trimmingCharacters(in: .whitespaces)), range.contains(count) else {
      return .failure(.invalid("expected \(range.lowerBound) to \(range.upperBound)"))
    }
    return .success(count)
  }

  static func choices(_ text: String) -> Result<[ContextCheckpointChoice], ConfigValueError> {
    var listed: [ContextCheckpointChoice] = []
    for entry in entries(text, separator: ",") {
      guard let choice = ContextCheckpointChoice(configName: entry), !listed.contains(choice),
        listed.count < ContextCheckpointChoices.maximumCount
      else { return .failure(.invalid(choicesShape)) }
      listed.append(choice)
    }
    guard let highlighted = listed.first else { return .failure(.invalid(choicesShape)) }
    return .success(
      ContextCheckpointChoices.ordered(Set(listed), highlighted: highlighted))
  }

  private static var choicesShape: String {
    let names = ContextCheckpointChoices.canonicalOrder.map(\.configName)
    return
      "expected 1 to \(ContextCheckpointChoices.maximumCount) different choices from"
      + " \(names.dropLast().joined(separator: ", ")) and \(names.last ?? "")"
  }
}
