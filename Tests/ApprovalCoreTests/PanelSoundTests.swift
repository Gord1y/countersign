import Foundation
import Testing

@testable import ApprovalCore

@Suite struct PanelSoundTests {
  private func parse(_ json: String, soundNames: [String] = PanelSound.systemNames) -> (
    file: ConfigFile, logLines: [String]
  ) {
    ConfigFileParser.parse(Data(json.utf8), soundNames: soundNames)
  }

  private func editing(_ original: String?, _ edit: PreferenceEdit) throws -> String {
    let bytes = try ConfigEdit.applying([edit], to: original.map { Array($0.utf8) })
    return String(decoding: bytes, as: UTF8.self)
  }

  @Test func defaultsToNone() {
    let (file, logLines) = parse("{}")
    #expect(file.panelSound == nil)
    #expect(logLines.isEmpty)
    #expect(Settings.resolve(file: file, host: .claude).panelSound == "none")
    #expect(Settings.defaultPanelSound == PanelSound.none)
    #expect(PreferenceValues().panelSound == "none")
  }

  @Test func readsNoneAndEveryKnownName() {
    #expect(parse(#"{ "panelSound": "none" }"#).file.panelSound == "none")
    for name in PanelSound.systemNames {
      let (file, logLines) = parse(#"{ "panelSound": "\#(name)" }"#)
      #expect(file.panelSound == name)
      #expect(logLines.isEmpty)
    }
  }

  @Test func readsOnlyTheNamesItIsHanded() {
    let (file, logLines) = parse(#"{ "panelSound": "Glass" }"#, soundNames: ["Glass"])
    #expect(file.panelSound == "Glass")
    #expect(logLines.isEmpty)
    let (missing, missingLines) = parse(#"{ "panelSound": "Ping" }"#, soundNames: ["Glass"])
    #expect(missing.panelSound == nil)
    #expect(missingLines.count == 1)
  }

  @Test func anUnknownNameFallsBackWithOneLogLine() {
    let expected = [
      #"panelSound: expected "none" or the name of a system sound, using default "none""#
    ]
    let (unknown, unknownLines) = parse(#"{ "panelSound": "Ding" }"#)
    #expect(unknown.panelSound == nil)
    #expect(unknownLines == expected)
    let (wrongCase, wrongCaseLines) = parse(#"{ "panelSound": "glass" }"#)
    #expect(wrongCase.panelSound == nil)
    #expect(wrongCaseLines == expected)
    let (wrongType, wrongTypeLines) = parse(#"{ "panelSound": true }"#)
    #expect(wrongType.panelSound == nil)
    #expect(wrongTypeLines == expected)
    #expect(Settings.resolve(file: unknown, host: .claude).panelSound == "none")
  }

  @Test func panelSoundIsNotAHostKey() {
    let (file, logLines) = parse(#"{ "hosts": { "codex": { "panelSound": "Glass" } } }"#)
    #expect(file.codex == ConfigFile.HostOverrides())
    #expect(logLines == [#"unknown key "hosts.codex.panelSound", ignored"#])
  }

  @Test func resolvesTheFileValueForEveryHost() {
    let file = ConfigFile(panelSound: "Hero")
    for host in Host.allCases {
      #expect(Settings.resolve(file: file, host: host).panelSound == "Hero")
    }
    #expect(PreferenceValues(file: file).panelSound == "Hero")
  }

  @Test func choicesPutNoneFirstThenTheInstalledNames() {
    #expect(PanelSound.choices(installed: ["Glass", "Ping"]) == ["none", "Glass", "Ping"])
    #expect(PanelSound.choices(installed: []) == ["none"])
  }

  @Test func silenceAndTitles() {
    #expect(PanelSound.isSilent("none"))
    #expect(!PanelSound.isSilent("Glass"))
    #expect(PanelSound.title("none") == "None")
    #expect(PanelSound.title("Glass") == "Glass")
  }

  @Test func listsTheFourteenSystemSounds() {
    #expect(PanelSound.systemNames.count == 14)
    #expect(Set(PanelSound.systemNames).count == 14)
  }

  @Test func editsWriteTheNameAtTheTopLevel() throws {
    let schema = SettingsPrompt.schemaURL
    #expect(
      try editing(nil, .panelSound("Glass"))
        == "{\n  \"$schema\": \"\(schema)\",\n  \"panelSound\": \"Glass\"\n}\n")
    #expect(
      try editing("{\"panelSound\": \"Glass\", \"idleSeconds\": 5}", .panelSound("none"))
        == "{\"panelSound\": \"none\", \"idleSeconds\": 5}")
    let config = "{\"panelSound\":\"Glass\"}"
    #expect(try editing(config, .panelSound("Glass")) == config)
    #expect(PreferenceEdit.panelSound("Glass").key == .panelSound)
    #expect(PreferenceName.panelSound.keyPath == ["panelSound"])
  }

  @Test func editsApplyAndResetToValues() {
    let values = PreferenceValues().applying(.panelSound("Frog"))
    #expect(values.panelSound == "Frog")
    #expect(values.applying(.reset(.panelSound)).panelSound == "none")
  }

  @Test func resetSeesOnlyANonDefaultSound() {
    #expect(PreferenceReset.isChanged(.panelSound, in: ConfigFile(panelSound: "Glass")))
    #expect(!PreferenceReset.isChanged(.panelSound, in: ConfigFile(panelSound: "none")))
    #expect(!PreferenceReset.isChanged(.panelSound, in: ConfigFile()))
    #expect(
      PreferenceReset.changedNames(
        in: ConfigFile(panelSound: "Glass"), within: SettingsPane.panels.preferenceNames)
        == [.panelSound])
    #expect(
      PreferenceReset.line(for: .panelSound, current: PreferenceValues(panelSound: "Glass"))
        == "Sound: Glass → None")
  }

  @Test func namesTheRowAndItsDefault() {
    #expect(PreferenceName.panelSound.title == "Sound")
    #expect(PreferenceName.panelSound.defaultText == "None")
    #expect(!PreferenceName.panelSound.caption.isEmpty)
    #expect(!PreferenceName.panelSound.explanation.isEmpty)
  }
}
