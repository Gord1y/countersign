import AppKit
import ApprovalCore
import Foundation

enum PreviewCommand {
  @MainActor
  static func run(_ arguments: [String]) {
    guard let options = parse(arguments) else {
      CommandLineOutput.fail(
        "usage: countersign preview --host claude|codex|cursor|antigravity <fixture.json> [--waiting N]"
      )
    }

    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: options.fixturePath))
    } catch {
      CommandLineOutput.fail("error: could not read \(options.fixturePath)")
    }

    let request: ApprovalRequest
    do {
      request = try options.host.parse(data)
    } catch {
      CommandLineOutput.fail(
        "error: could not parse \(options.fixturePath) as a \(options.host.displayName) request")
    }

    let diagnosticLog: (String) -> Void = { FileHandle.standardError.write(Data("\($0)\n".utf8)) }
    let app = PanelApplication(log: diagnosticLog)

    let (configFile, configLogLines) = ConfigFileLoader.load(
      paths: AppPaths.standard, soundNames: SystemSounds.installedNames)
    for line in configLogLines {
      diagnosticLog(line)
    }
    let settings = Settings.resolve(file: configFile, host: options.host)

    let chatTrackingDrift = ChatTrackingHealth.evaluate(
      request: request, sessionsDirectory: AppPaths.standard.claudeSessionsDirectory)
    if let chatTrackingDrift {
      diagnosticLog("chat tracking: \(chatTrackingDrift.reason)")
    }

    let subagentChain = SubagentDescription.chain(for: request)
    let waitingEntries = Array(
      repeating: WaitingEntry(
        summary: TicketSummary(
          request: request, agentDescription: SubagentDescription.resolve(from: subagentChain))),
      count: options.waitingCount)
    let controller = PanelController(
      request: request, waitingEntries: waitingEntries, armDuration: settings.armDelay,
      snoozeMinutes: settings.snoozeMinutes, questionNotes: settings.questionNotes,
      modeAfterPlan: settings.modeAfterPlan, panelSound: settings.panelSound,
      appearance: settings.appearance, accentColor: settings.accentColor,
      chatTrackingDrift: chatTrackingDrift, subagentChain: subagentChain,
      onFinish: { outcome in
        if let data = options.host.encode(outcome), let string = String(data: data, encoding: .utf8)
        {
          print(string)
        } else {
          print("no decision")
        }
        exit(0)
      },
      onSnooze: { seconds in
        print("snoozed \(Int(seconds))")
        exit(0)
      },
      onStepAside: { reason in
        print("stepped aside: \(reason.rawValue)")
        exit(0)
      })
    app.show(controller)
    app.run()
    exit(0)
  }

  private struct Options {
    let host: ApprovalCore.Host
    let fixturePath: String
    let waitingCount: Int
  }

  private static func parse(_ arguments: [String]) -> Options? {
    var host: ApprovalCore.Host?
    var fixturePath: String?
    var waitingCount = 0
    var index = arguments.startIndex

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--host":
        index += 1
        guard index < arguments.count,
          let parsedHost = ApprovalCore.Host(rawValue: arguments[index])
        else {
          return nil
        }
        host = parsedHost
      case "--waiting":
        index += 1
        guard index < arguments.count, let count = Int(arguments[index]) else {
          return nil
        }
        waitingCount = count
      default:
        guard fixturePath == nil else { return nil }
        fixturePath = argument
      }
      index += 1
    }

    guard let host, let fixturePath else { return nil }
    return Options(host: host, fixturePath: fixturePath, waitingCount: waitingCount)
  }
}
