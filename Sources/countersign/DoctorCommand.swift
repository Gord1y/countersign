import ApprovalCore
import Foundation

enum DoctorCommand {
  static let usage = "usage: countersign doctor"

  static func run(_ arguments: [String]) {
    guard arguments.isEmpty else {
      CommandLineOutput.fail(usage)
    }
    let lines = Doctor.report(gatherInput())
    for line in lines {
      print(line.text)
    }
    exit(Doctor.exitCode(for: lines))
  }

  static func gatherInput() -> Doctor.Input {
    let paths = AppPaths.standard
    let environment = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser
    let resolvedExecutablePath =
      Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "(unresolved)"
    let stableExecutablePath = StableExecutablePath.stable(
      forResolved: resolvedExecutablePath, home: home,
      isExecutable: FileManager.default.isExecutableFile(atPath:))

    let hosts = ApprovalCore.Host.allCases.map {
      hostInput(for: $0, environment: environment, home: home)
    }

    let configExists = FileManager.default.fileExists(atPath: paths.configFile.path)
    let (configFile, configLogLines) = ConfigFileLoader.load(
      paths: paths, soundNames: SystemSounds.installedNames)

    let queue = TicketQueue(directory: paths.queueDirectory, lockFile: paths.displayLockFile)
    let liveTicketCount = queue.liveTickets().count

    let pauseSwitch = PauseSwitch(file: paths.pauseFile)
    let quietState = QuietState(paths: paths, schedule: configFile.quietSchedule)
    let quietUntilDescription = quietState.activeUntil().map(formattedTime)

    let logSize =
      (try? FileManager.default.attributesOfItem(atPath: paths.logFile.path))?[.size]
      as? Int

    var input = Doctor.Input(
      version: CountersignVersion.current,
      resolvedExecutablePath: resolvedExecutablePath,
      stableExecutablePath: stableExecutablePath,
      hosts: hosts,
      configPath: paths.configFile.path,
      configFileExists: configExists,
      configLogLines: configLogLines,
      queueDirectoryPath: paths.queueDirectory.path,
      liveTicketCount: liveTicketCount,
      pauseState: pauseSwitch.state,
      quietUntilDescription: quietUntilDescription,
      logFilePath: paths.logFile.path,
      logFileSize: logSize)
    input.duplicateInstall = InstallCopiesCheck.duplicates(
      hookExecutables: hosts.flatMap { $0.executableChecks.keys },
      runningExecutable: Bundle.main.executableURL?.resolvingSymlinksInPath().path, home: home)
    input.installVersionMismatch = InstallCopiesCheck.versionMismatch(home: home)
    input.contextCheckpointsEnabled =
      Settings.resolve(file: configFile, host: .claude).contextCheckpoints.enabled
    input.waitingNoticesEnabled =
      Settings.resolve(file: configFile, host: .claude).waitingNotices
    input.rules = Settings.resolve(file: configFile, host: .claude).rules
    input.codexHookTrustRecord = CodexHookTrustRecordStore.load(file: paths.codexHookTrustFile)
    input.codexWaitingHookTrustRecord = CodexHookTrustRecordStore.load(
      file: paths.codexWaitingHookTrustFile)
    input.codexConfigFile = readFileState(
      CodexHookTrust.configFile(
        for: HookConfigLocation.location(for: .codex, environment: environment, home: home)))
    return input
  }

  private static func hostInput(
    for host: ApprovalCore.Host, environment: [String: String], home: URL
  ) -> Doctor.HostInput {
    let location = HookConfigLocation.location(for: host, environment: environment, home: home)
    let directoryExists = isInstalled(location)
    let fileState = readFileState(location.file)
    var executableChecks: [String: Bool] = [:]
    if case .bytes(let bytes) = fileState {
      for path in Doctor.executablePaths(inHookConfig: bytes, host: host) {
        executableChecks[path] = FileManager.default.isExecutableFile(atPath: path)
      }
    }
    return Doctor.HostInput(
      host: host, directoryPath: location.hostDirectoryPaths, filePath: location.file.path,
      directoryExists: directoryExists, fileState: fileState, executableChecks: executableChecks)
  }

  static func isInstalled(_ location: HookConfigLocation) -> Bool {
    location.hostDirectories.contains(where: isDirectory)
  }

  static func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private static func readFileState(_ file: URL) -> Doctor.FileState {
    do {
      guard let bytes = try ConfigFileStore.read(file) else { return .missing }
      return .bytes(bytes)
    } catch {
      return .unreadable("\(error)")
    }
  }

  private static func formattedTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
