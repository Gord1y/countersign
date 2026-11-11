import AppKit
import ApprovalCore
import Foundation

enum TestCardCommand {
  static let usage = TestCardCommandLine.usage

  @MainActor
  static func run(_ arguments: [String]) -> Never {
    guard let kindName = TestCardCommandLine.parse(arguments) else {
      CommandLineOutput.fail(usage)
    }
    let kind: TestCornerCardKind
    switch kindName {
    case .notice: kind = .notice
    case .approval: kind = .approval
    }
    let paths = AppPaths.standard
    let (configFile, _) = ConfigFileLoader.load(
      paths: paths, soundNames: SystemSounds.installedNames)
    let preferences = PreferenceValues(file: configFile)

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    let cards = TestCornerCards()
    let outcome = cards.show(
      kind, store: WaitingStore(directory: paths.waitingDirectory),
      appearance: preferences.appearance, noticeDuration: preferences.waitingNoticeDuration,
      onShowTestPanel: { launchCommandPanel() })
    if outcome == .noFreeSlot {
      CommandLineOutput.fail("error: \(TestCornerCards.noFreeSlotMessage)")
    }
    print("showing a test \(kindName.rawValue) card; nothing reaches an agent")
    Task { @MainActor in
      while !(cards.isEmpty && !TestPanelLauncher.shared.isRunning) {
        try? await Task.sleep(for: .milliseconds(200))
      }
      exit(0)
    }
    application.run()
    exit(0)
  }

  @MainActor
  private static func launchCommandPanel() {
    do {
      try TestPanelLauncher.shared.launch(kind: .command) { refusal in
        FileHandle.standardError.write(Data("countersign: \(refusal)\n".utf8))
      }
    } catch {
      FileHandle.standardError.write(
        Data("countersign: the test panel could not start: \(SetupRun.describe(error))\n".utf8))
    }
  }
}
