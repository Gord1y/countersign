import ApprovalCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

if AppLaunchMode.detect(bundleIdentifier: Bundle.main.bundleIdentifier, arguments: arguments)
  == .app
{
  MenuBarCompanion.run()
}

switch arguments.first {
case "hook":
  HookRunner.run(Array(arguments.dropFirst()))
case "setup":
  SetupCommand.run(Array(arguments.dropFirst()))
case "settings":
  SettingsCommand.run(Array(arguments.dropFirst()))
case "doctor":
  DoctorCommand.run(Array(arguments.dropFirst()))
case "preview":
  PreviewCommand.run(Array(arguments.dropFirst()))
case "test-panel":
  TestPanelCommand.run(Array(arguments.dropFirst()))
case "snapshot":
  SnapshotCommand.run(Array(arguments.dropFirst()))
case "pause":
  StatusCommand.pause()
case "resume":
  StatusCommand.resume()
case "status":
  StatusCommand.status()
case "snooze":
  StatusCommand.snooze(Array(arguments.dropFirst()))
case "help", "--help", "-h":
  print(CommandLineHelp.text(version: CountersignVersion.current))
case "--version":
  print("countersign \(CountersignVersion.current)")
default:
  CommandLineOutput.fail(
    "usage: countersign"
      + " <hook|setup|settings|doctor|preview|test-panel|snapshot|pause|resume|snooze|status"
      + "|help|--version>\n"
      + "run countersign help for the commands and links"
  )
}
