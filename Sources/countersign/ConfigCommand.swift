import ApprovalCore
import Foundation

enum ConfigCommand {
  static let usage = ConfigCommandLine.usage

  static func run(_ arguments: [String]) {
    guard let command = ConfigCommandLine.parse(arguments) else {
      CommandLineOutput.fail(usage)
    }
    let paths = AppPaths.standard
    switch command {
    case .unknownKey(let key):
      CommandLineOutput.fail(ConfigCommandLine.unknownKeyError(key))
    case .unknownPane(let pane):
      CommandLineOutput.fail(ConfigCommandLine.unknownPaneError(pane))
    case .open:
      open(paths: paths)
    default:
      CommandLineOutput.failOnUnusableConfig(paths: paths)
      let file = ConfigFileLoader.load(paths: paths).file
      handle(command, file: file, paths: paths)
    }
  }

  private static func handle(_ command: ConfigCommandLine, file: ConfigFile, paths: AppPaths) {
    let values = PreferenceValues(file: file)
    switch command {
    case .list:
      for name in PreferenceName.allCases {
        print(ConfigCommandLine.row(name, values: values))
      }
    case .get(let name):
      print(ConfigValue.text(name, values: values))
    case .set(let name, let text):
      switch ConfigValue.edits(for: name, text: text, current: values) {
      case .failure(let error):
        CommandLineOutput.fail(error.description)
      case .success(let edits):
        change(name, edits: edits, file: file, paths: paths)
      }
    case .reset(let name):
      if let refusal = ConfigValue.resetRefusal(name) {
        CommandLineOutput.fail(refusal.description)
      }
      change(name, edits: [.reset(name)], file: file, paths: paths)
    case .resetPane(let pane):
      resetPane(pane, file: file, values: values, paths: paths)
    case .open, .unknownKey, .unknownPane:
      CommandLineOutput.fail(usage)
    }
  }

  private static func write(_ edits: [PreferenceEdit], paths: AppPaths) {
    do {
      try PreferenceFileWriter.apply(edits, configFile: paths.configFile)
    } catch {
      CommandLineOutput.fail("error: \(SetupRun.describe(error))")
    }
  }

  private static func change(
    _ name: PreferenceName, edits: [PreferenceEdit], file: ConfigFile, paths: AppPaths
  ) {
    write(edits, paths: paths)
    let reloaded = PreferenceValues(file: ConfigFileLoader.load(paths: paths).file)
    print("\(name.commandLineKey) = \(ConfigValue.text(name, values: reloaded))")
    if PreferenceReset.hasHostValues(for: [name], in: file) {
      print(PreferenceReset.hostsNote)
    }
  }

  private static func resetPane(
    _ pane: SettingsPane, file: ConfigFile, values: PreferenceValues, paths: AppPaths
  ) {
    guard !pane.preferenceNames.isEmpty else {
      CommandLineOutput.fail(ConfigCommandLine.noSettingsError(pane))
    }
    let changed = PreferenceReset.changedNames(in: file, within: pane.preferenceNames)
      .filter { ConfigValue.resetRefusal($0) == nil }
    guard !changed.isEmpty else {
      print(ConfigCommandLine.alreadyDefaults)
      return
    }
    let lines = PreferenceReset.confirmationLines(
      changed: changed, group: pane.preferenceNames, current: values, file: file)
    write(changed.map { PreferenceEdit.reset($0) }, paths: paths)
    for line in lines {
      print(line)
    }
  }

  private static func open(paths: AppPaths) {
    do {
      _ = try ConfigFileStarter.createIfMissing(paths: paths)
    } catch {
      CommandLineOutput.fail("error: \(SetupRun.describe(error))")
    }
    let path = paths.configFile.path
    let editor = ConfigFileLoader.load(paths: paths).file.editorApp
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = editor.map { ["-b", $0, path] } ?? ["-t", path]
    let failure =
      "error: could not open \(path);"
      + " set an editor with countersign config set editorApp <bundle id>"
    do {
      try process.run()
    } catch {
      CommandLineOutput.fail(failure)
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { CommandLineOutput.fail(failure) }
    print("opened \(path)")
  }
}
