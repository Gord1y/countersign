import ApprovalCore
import Foundation

enum AppControlCommand {
  private static let pollInterval: TimeInterval = 0.1
  private static let pollLimit: TimeInterval = 5

  static func quit(_ arguments: [String]) {
    guard let pausing = AppControlCommandLine.parseQuit(arguments) else {
      CommandLineOutput.fail(AppControlCommandLine.quitUsage)
    }
    let paths = AppPaths.standard
    guard CompanionProbe.isRunning(paths: paths) else {
      print(AppControlCommandLine.notRunning)
      return
    }
    let alreadyPaused = PauseSwitch(file: paths.pauseFile).state != .active
    post(
      pausing
        ? CompanionLaunch.quitPausingNotificationName : CompanionLaunch.quitNotificationName)
    let quit = wait { !CompanionProbe.isRunning(paths: paths) }
    guard quit else { CommandLineOutput.fail(AppControlCommandLine.didNotQuit) }
    print(AppControlCommandLine.quitMessage(pausing: pausing, alreadyPaused: alreadyPaused))
  }

  static func launchAtLogin(_ arguments: [String]) {
    guard let on = AppControlCommandLine.parseLaunchAtLogin(arguments) else {
      CommandLineOutput.fail(AppControlCommandLine.launchAtLoginUsage)
    }
    let paths = AppPaths.standard
    guard CompanionProbe.isRunning(paths: paths) else {
      CommandLineOutput.fail(AppControlCommandLine.launchNeedsApp)
    }
    let replyFile = paths.launchAtLoginReplyFile
    try? FileManager.default.removeItem(at: replyFile)
    post(
      on
        ? CompanionLaunch.launchAtLoginOnNotificationName
        : CompanionLaunch.launchAtLoginOffNotificationName)
    let answered = wait { FileManager.default.fileExists(atPath: replyFile.path) }
    guard answered,
      let text = try? String(contentsOf: replyFile, encoding: .utf8),
      let reply = LaunchAtLoginReply(encoded: text)
    else {
      try? FileManager.default.removeItem(at: replyFile)
      CommandLineOutput.fail(AppControlCommandLine.didNotAnswer)
    }
    try? FileManager.default.removeItem(at: replyFile)
    switch AppControlCommandLine.launchAtLoginMessage(on: on, reply: reply) {
    case .success(let message): print(message)
    case .failure(let failure): CommandLineOutput.fail(failure.description)
    }
  }

  private static func post(_ name: String) {
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
  }

  private static func wait(until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(pollLimit)
    while Date() < deadline {
      if condition() { return true }
      Thread.sleep(forTimeInterval: pollInterval)
    }
    return condition()
  }
}
