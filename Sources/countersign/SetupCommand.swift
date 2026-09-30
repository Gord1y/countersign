import ApprovalCore
import Darwin
import Foundation

enum SetupCommand {
  static let usage =
    "usage: countersign setup [--cli [--yes] [--uninstall] [--host claude|codex|cursor|antigravity]]"

  @MainActor
  static func run(_ arguments: [String]) {
    switch SetupOptions.mode(for: arguments) {
    case nil:
      CommandLineOutput.fail(usage)
    case .window:
      SettingsCommand.openWindow()
    case .terminal(let options):
      runInTerminal(options)
    }
  }

  private static func runInTerminal(_ options: SetupOptions) -> Never {
    let environment = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates = options.hosts.map {
      HookConfigLocation.location(for: $0, environment: environment, home: home)
    }
    let detected = candidates.filter(DoctorCommand.isInstalled)
    guard !detected.isEmpty else {
      let looked = candidates.map { "\($0.host.displayName) (\($0.hostDirectoryPaths))" }
      print("no host detected: looked for \(looked.joined(separator: ", "))")
      printDuplicateInstall(environment: environment, home: home)
      exit(0)
    }
    var executablePath = ""
    if !options.uninstall {
      guard let resolved = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
        CommandLineOutput.fail("error: could not resolve the countersign executable")
      }
      executablePath = StableExecutablePath.stable(
        forResolved: resolved, home: home,
        isExecutable: FileManager.default.isExecutableFile(atPath:))
    }
    let interactive = isatty(STDIN_FILENO) == 1
    var setup = SetupRun(
      executablePath: executablePath, uninstall: options.uninstall,
      codexHookTrustFile: AppPaths(home: home).codexHookTrustFile,
      codexWaitingHookTrustFile: AppPaths(home: home).codexWaitingHookTrustFile,
      output: { print($0, terminator: "") },
      confirm: { confirmed(options: options, interactive: interactive, path: $0) })
    var failed = false
    for location in detected {
      let succeeded = setup.apply(location)
      failed = failed || !succeeded
    }
    printFollowUps(
      uninstall: options.uninstall, changedFiles: setup.changedFiles, environment: environment,
      home: home)
    printDuplicateInstall(environment: environment, home: home)
    exit(failed ? 1 : 0)
  }

  private static func printFollowUps(
    uninstall: Bool, changedFiles: [URL], environment: [String: String], home: URL
  ) {
    guard let resolved = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { return }
    let stablePath = StableExecutablePath.stable(
      forResolved: resolved, home: home, isExecutable: FileManager.default.isExecutableFile(atPath:)
    )
    let locations = ApprovalCore.Host.allCases.map {
      HookConfigLocation.location(for: $0, environment: environment, home: home)
    }
    var wiring: [ApprovalCore.Host: HostWiringStatus] = [:]
    var codexTrust = CodexHookTrustState.unknown
    for location in locations {
      let status = HostWiring.status(
        host: location.host, directoryExists: DoctorCommand.isInstalled(location),
        file: ConfigFileStore.fileState(location.file), stablePath: stablePath)
      wiring[location.host] = status
      if location.host == .codex, status == .wired {
        codexTrust = CodexHookTrust.check(
          location, recordFile: AppPaths(home: home).codexHookTrustFile, persistsLearnedHash: true)
      }
    }
    let changedHosts = Set(locations.filter { changedFiles.contains($0.file) }.map(\.host))
    for line in AgentFollowUps.setupLines(
      wiring: wiring, codexTrust: codexTrust, changedHosts: changedHosts, uninstall: uninstall)
    {
      print(line)
    }
  }

  private static func printDuplicateInstall(environment: [String: String], home: URL) {
    let locations = ApprovalCore.Host.allCases.map {
      HookConfigLocation.location(for: $0, environment: environment, home: home)
    }
    guard
      let duplicateInstall = InstallCopiesCheck.duplicates(
        hookExecutables: InstallCopiesCheck.hookExecutables(in: locations),
        runningExecutable: Bundle.main.executableURL?.resolvingSymlinksInPath().path, home: home)
    else { return }
    print(duplicateInstall.doctorLine.text)
  }

  private static func confirmed(options: SetupOptions, interactive: Bool, path: String) -> Bool {
    if options.assumeYes {
      return true
    }
    guard interactive else {
      print("\(path): not applied, stdin is not a terminal (pass --yes to apply)")
      return false
    }
    print("Apply? [y/N] ", terminator: "")
    fflush(stdout)
    guard HookSetup.isConfirmation(readLine()) else {
      print("\(path): skipped")
      return false
    }
    return true
  }
}
