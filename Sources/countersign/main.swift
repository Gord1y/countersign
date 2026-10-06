import ApprovalCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

if AppLaunchMode.detect(bundleIdentifier: Bundle.main.bundleIdentifier, arguments: arguments)
  == .app
{
  MenuBarCompanion.run()
}

@MainActor
func usage(ofCommand command: String?) -> String? {
  switch command {
  case "setup": SetupCommand.usage
  case "settings": SettingsCommand.usage
  case "doctor": DoctorCommand.usage
  case "preview": PreviewCommand.usage
  case "test-panel": TestPanelCommand.usage
  case "snapshot": SnapshotCommand.usage
  case "pause": StatusCommand.pauseUsage
  case "resume": StatusCommand.resumeUsage
  case "status": StatusCommand.statusUsage
  case "snooze": StatusCommand.snoozeUsage
  default: nil
  }
}

if let usage = usage(ofCommand: arguments.first),
  CommandHelp.isRequest(Array(arguments.dropFirst()))
{
  print(usage)
  exit(0)
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
case WaitingRecorder.noticeCommand:
  WaitingNoticeCommand.run(Array(arguments.dropFirst()))
case "pause":
  StatusCommand.pause(Array(arguments.dropFirst()))
case "resume":
  StatusCommand.resume(Array(arguments.dropFirst()))
case "status":
  StatusCommand.status(Array(arguments.dropFirst()))
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
