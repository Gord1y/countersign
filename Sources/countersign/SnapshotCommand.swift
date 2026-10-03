import AppKit
import ApprovalCore
import SwiftUI

enum SnapshotCommand {
  private static let usage =
    "usage: countersign snapshot <request.json> --host claude|codex|cursor|antigravity"
    + " [--waiting N] [--appearance light|dark] [--accent #RRGGBB] [--unarmed] [--question-notes]"
    + " [--open-menu approve|snooze|mode] -o <out.png>\n"
    + "       countersign snapshot --test-panel command|question|plan|context"
    + " [--waiting N] [--appearance light|dark] [--accent #RRGGBB] [--unarmed] [--question-notes]"
    + " [--open-menu approve|snooze|mode] [--checkpoint-level soft|status|insist]"
    + " -o <out.png>\n"
    + "       countersign snapshot --settings"
    + " [--home <dir>] [--show-changes claude|codex|cursor|antigravity] [--show-copies]"
    + " [--status active|paused|paused-until-open|quiet] [--size <width>x<height>]"
    + " [--tab agents|panels|app|rules|context|help|advanced] [--restore-prompt panels|app]"
    + " [--explanation <preferenceName>] [--editor-choice ask|missing]"
    + " [--appearance light|dark] -o <out.png>\n"
    + "       countersign snapshot --quit-prompt [--appearance light|dark] -o <out.png>\n"
    + "       countersign snapshot --update-answer up-to-date|available|failed"
    + " [--appearance light|dark] -o <out.png>\n"
    + "       countersign snapshot --tour 1|2|3|4 [--appearance light|dark] -o <out.png>\n"
    + "       countersign snapshot --menu-bar-icon active|paused|quiet"
    + " [--appearance light|dark] -o <out.png>\n"
    + "       countersign snapshot --waiting-notice claude|codex|cursor|antigravity"
    + " [--project <name>] [--no-app] [--appearance light|dark] -o <out.png>\n"
    + "       countersign snapshot --approval-card claude|codex|cursor|antigravity"
    + " [--project <name>] [--appearance light|dark] -o <out.png>"
  private static let quietSnapshotMinutes: TimeInterval = 15
  private static let settingsFlag = "--settings"
  private static let quitPromptFlag = "--quit-prompt"
  private static let updateAnswerFlag = "--update-answer"
  private static let tourFlag = "--tour"
  private static let menuBarIconFlag = "--menu-bar-icon"
  private static let waitingNoticeFlag = "--waiting-notice"
  private static let approvalCardFlag = "--approval-card"
  private static let waitingNoticeSampleProject = "shop-api"
  private static let menuBarIconStripPadding: CGFloat = 6
  private static let scale: CGFloat = 2
  private static let settleTurnLimit = 50
  private static let stableTurnsNeeded = 3

  @MainActor
  static func run(_ arguments: [String]) {
    if arguments.contains(settingsFlag) {
      runSettings(arguments)
    }
    if arguments.contains(quitPromptFlag) {
      runQuitPrompt(arguments)
    }
    if arguments.contains(updateAnswerFlag) {
      runUpdateAnswer(arguments)
    }
    if arguments.contains(tourFlag) {
      runTour(arguments)
    }
    if arguments.contains(menuBarIconFlag) {
      runMenuBarIcon(arguments)
    }
    if arguments.contains(waitingNoticeFlag) {
      runCornerCard(arguments, flag: waitingNoticeFlag)
    }
    if arguments.contains(approvalCardFlag) {
      runCornerCard(arguments, flag: approvalCardFlag)
    }
    guard let options = parse(arguments) else { CommandLineOutput.fail(usage) }

    let request = loadRequest(options.source, checkpointLevel: options.checkpointLevel)
    let isTestPanel = options.source.isTestPanel

    NSApplication.shared.setActivationPolicy(.prohibited)

    let screen = PanelController.resolveTargetScreen()
    let width = PanelController.panelWidth(screen: screen)
    let maxHeight = PanelController.maxContentHeight(screen: screen)

    let subagentChain = SubagentDescription.chain(for: request)
    let waitingEntries = Array(
      repeating: WaitingEntry(
        summary: TicketSummary(
          request: request, agentDescription: SubagentDescription.resolve(from: subagentChain))),
      count: options.waitingCount)
    let chatTrackingDrift =
      isTestPanel ? nil : ChatTrackingHealth.evaluateTranscript(request: request)
    CountersignPalette.use(options.accentColor)
    let model = PanelModel(
      request: request, waitingEntries: waitingEntries, questionNotes: options.questionNotes,
      chatTrackingDrift: chatTrackingDrift, subagentChain: subagentChain,
      isTestPanel: isTestPanel, openDropdownOnAppear: options.openMenu)
    model.onSnooze = { _ in }
    if options.isArmed {
      model.arm()
    }

    let hostingView = NSHostingView(
      rootView: PanelRootView(model: model, width: width, maxHeight: maxHeight)
        .environment(\.panelSurface, .solid))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: maxHeight),
      styleMask: [.borderless], backing: .buffered, defer: true, screen: screen)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.appearance = options.appearance?.appearance
    window.contentView = hostingView

    let height = settledHeight(of: hostingView, maxHeight: maxHeight)
    window.setContentSize(NSSize(width: width, height: height))
    _ = settledHeight(of: hostingView, maxHeight: maxHeight)

    if let openMenu = options.openMenu, !model.dropdown.isOpen {
      CommandLineOutput.fail("error: this panel has no \(openMenu.rawValue) menu")
    }
    guard let png = render(hostingView) else {
      CommandLineOutput.fail("error: could not render the panel")
    }
    write(png, to: options.outputPath)
  }

  private static func loadRequest(_ source: RequestSource, checkpointLevel: ContextLevel?)
    -> ApprovalRequest
  {
    switch source {
    case .file(let path, let host):
      let data: Data
      do {
        data = try Data(contentsOf: URL(fileURLWithPath: path))
      } catch {
        CommandLineOutput.fail("error: could not read \(path)")
      }
      do {
        return try host.parse(data)
      } catch {
        CommandLineOutput.fail("error: could not parse \(path) as a \(host.displayName) request")
      }
    case .testPanel(let kind):
      if kind == .context, let checkpointLevel {
        return TestPanelSample.contextRequest(level: checkpointLevel, settings: .default)
      }
      do {
        return try TestPanelSample.request(for: kind)
      } catch {
        CommandLineOutput.fail("error: could not build the \(kind.rawValue) test panel")
      }
    }
  }

  @MainActor
  private static func runSettings(_ arguments: [String]) -> Never {
    guard let options = parseSettings(arguments) else { CommandLineOutput.fail(usage) }

    NSApplication.shared.setActivationPolicy(.prohibited)

    if let name = options.explanation {
      runExplanation(name: name, appearance: options.appearance, outputPath: options.outputPath)
    }

    let environment = options.home.map(SettingsEnvironment.current(home:)) ?? .current()
    if let choice = options.editorChoice {
      runEditorChoice(
        choice: choice, configFile: environment.paths.configFile,
        appearance: options.appearance, outputPath: options.outputPath)
    }
    let model = SettingsModel(
      environment: environment, status: options.status.status, savesLearnedCodexTrust: false)
    model.select(options.pane)
    for host in options.disclosedHosts {
      model.toggleChanges(host)
    }
    if options.showsCopies, model.duplicateInstall != nil {
      model.toggleCopies()
    }

    if let restorePane = options.restorePrompt {
      runRestorePrompt(
        model: model, pane: restorePane, appearance: options.appearance,
        outputPath: options.outputPath)
    }

    let size = options.size ?? fullSettingsSize(of: model)
    let hostingView = NSHostingView(rootView: SettingsRootView(model: model))
    hostingView.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless], backing: .buffered, defer: true)
    window.appearance = options.appearance?.appearance ?? model.appearance.windowAppearance
    window.contentView = hostingView
    _ = settledHeight(of: hostingView, maxHeight: size.height)

    guard let png = render(hostingView) else {
      CommandLineOutput.fail("error: could not render the settings")
    }
    write(png, to: options.outputPath)
  }

  @MainActor
  private static func fullSettingsSize(of model: SettingsModel) -> CGSize {
    let width = SettingsWindowPlacement.defaultContentSize.width
    let measuringView = NSHostingView(
      rootView: VStack(spacing: 0) {
        SettingsHeader(model: model)
        HStack(alignment: .top, spacing: SettingsMetrics.sectionSpacing) {
          SettingsSidebar(model: model)
            .frame(width: SettingsMetrics.sidebarWidth, alignment: .leading)
          SettingsContent(model: model)
        }
        .padding(.horizontal, SettingsMetrics.padding)
      }
      .frame(width: width))
    let contentHeight = settledHeight(of: measuringView, maxHeight: .greatestFiniteMagnitude)
    return CGSize(width: width, height: contentHeight)
  }

  @MainActor
  private static func runEditorChoice(
    choice: EditorChoice, configFile: URL, appearance: Appearance?, outputPath: String
  ) -> Never {
    let hostingView = NSHostingView(
      rootView: EditorChoiceSheet(
        choice: choice, configFile: configFile, onOpen: { _, _ in }, onCancel: {}))
    hostingView.appearance = appearance?.appearance
    var size = hostingView.fittingSize
    for _ in 0..<settleTurnLimit {
      hostingView.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      let measured = hostingView.fittingSize
      if measured == size { break }
      size = measured
    }
    hostingView.setFrameSize(size)
    guard let png = render(hostingView, background: .windowBackgroundColor) else {
      CommandLineOutput.fail("error: could not render the editor choice")
    }
    write(png, to: outputPath)
  }

  @MainActor
  private static func runExplanation(
    name: PreferenceName, appearance: Appearance?, outputPath: String
  ) -> Never {
    let hostingView = NSHostingView(
      rootView: SettingsExplanationView(
        explanation: name.explanation, defaultText: name.defaultText))
    hostingView.appearance = appearance?.appearance
    var size = hostingView.fittingSize
    for _ in 0..<settleTurnLimit {
      hostingView.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      let measured = hostingView.fittingSize
      if measured == size { break }
      size = measured
    }
    hostingView.setFrameSize(size)
    guard let png = render(hostingView, background: .windowBackgroundColor) else {
      CommandLineOutput.fail("error: could not render the explanation")
    }
    write(png, to: outputPath)
  }

  @MainActor
  private static func runRestorePrompt(
    model: SettingsModel, pane: SettingsPane, appearance: Appearance?, outputPath: String
  ) -> Never {
    let lines = model.restoreDefaultsConfirmationLines(for: pane)
    let alert = RestoreDefaultsPrompt.makeAlert(pane: pane, lines: lines)
    alert.window.appearance = appearance?.appearance
    alert.layout()
    for _ in 0..<settleTurnLimit {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    guard let contentView = alert.window.contentView,
      let png = render(contentView, background: .windowBackgroundColor)
    else {
      CommandLineOutput.fail("error: could not render the restore prompt")
    }
    write(png, to: outputPath)
  }

  @MainActor
  private static func runQuitPrompt(_ arguments: [String]) -> Never {
    guard let options = parseQuitPrompt(arguments) else { CommandLineOutput.fail(usage) }

    NSApplication.shared.setActivationPolicy(.prohibited)

    let alert = QuitPrompt.makeAlert()
    alert.window.appearance = options.appearance?.appearance
    alert.layout()
    for _ in 0..<settleTurnLimit {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    guard let contentView = alert.window.contentView,
      let png = render(contentView, background: .windowBackgroundColor)
    else {
      CommandLineOutput.fail("error: could not render the quit prompt")
    }
    write(png, to: options.outputPath)
  }

  @MainActor
  private static func runUpdateAnswer(_ arguments: [String]) -> Never {
    guard let options = parseUpdateAnswer(arguments) else { CommandLineOutput.fail(usage) }

    NSApplication.shared.setActivationPolicy(.prohibited)

    let outcome = options.kind.outcome
    let releaseNotesURL: URL?
    if case .newerAvailable(let version) = outcome {
      releaseNotesURL = UpdateCommand.releaseNotesURL(version: version)
    } else {
      releaseNotesURL = nil
    }
    let answer = UpdateCheckAnswer.answer(
      for: outcome, currentVersion: CountersignVersion.current,
      upgradeCommand: UpdateCommand.curlInstallCommand, releaseNotesURL: releaseNotesURL)
    let alert = UpdateCheckAlert.makeAlert(for: answer)
    alert.window.appearance = options.appearance?.appearance
    alert.layout()
    for _ in 0..<settleTurnLimit {
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    guard let contentView = alert.window.contentView,
      let png = render(contentView, background: .windowBackgroundColor)
    else {
      CommandLineOutput.fail("error: could not render the update answer")
    }
    write(png, to: options.outputPath)
  }

  @MainActor
  private static func runTour(_ arguments: [String]) -> Never {
    guard let options = parseTour(arguments) else { CommandLineOutput.fail(usage) }

    NSApplication.shared.setActivationPolicy(.prohibited)

    let hostingView = NSHostingView(rootView: FirstRunTourView(step: options.step))
    hostingView.appearance = options.appearance?.appearance
    var size = hostingView.fittingSize
    for _ in 0..<settleTurnLimit {
      hostingView.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      let measured = hostingView.fittingSize
      if measured == size { break }
      size = measured
    }
    hostingView.setFrameSize(size)
    guard let png = render(hostingView, background: .windowBackgroundColor) else {
      CommandLineOutput.fail("error: could not render the tour")
    }
    write(png, to: options.outputPath)
  }

  @MainActor
  private static func runCornerCard(_ arguments: [String], flag: String) -> Never {
    guard let options = parseCornerCard(arguments, flag: flag) else {
      CommandLineOutput.fail(usage)
    }

    NSApplication.shared.setActivationPolicy(.prohibited)

    let isApprovalCard = flag == approvalCardFlag
    let model =
      isApprovalCard
      ? CornerCardModel.approval(hostName: options.host.displayName, projectName: options.project)
      : CornerCardModel.waitingNotice(
        hostName: options.host.displayName, projectName: options.project,
        offersGoThere: options.offersGoThere)
    let hostingView = NSHostingView(
      rootView: CornerCardView(model: model).environment(\.panelSurface, .solid))
    hostingView.appearance = options.appearance?.appearance
    let height = settledHeight(of: hostingView, maxHeight: .greatestFiniteMagnitude)
    hostingView.setFrameSize(NSSize(width: CornerCardView.width, height: height))
    guard let png = render(hostingView) else {
      CommandLineOutput.fail(
        "error: could not render the \(isApprovalCard ? "approval card" : "waiting notice")")
    }
    write(png, to: options.outputPath)
  }

  private static func runMenuBarIcon(_ arguments: [String]) -> Never {
    guard let options = parseMenuBarIcon(arguments) else { CommandLineOutput.fail(usage) }

    guard
      let png = renderMenuBarIcon(options.icon, appearance: options.appearance ?? .light)
    else {
      CommandLineOutput.fail("error: could not render the menu-bar icon")
    }
    write(png, to: options.outputPath)
  }

  private static func renderMenuBarIcon(_ icon: CompanionIcon, appearance: Appearance) -> Data? {
    let canvas = CGSize(width: MenuBarIcon.canvasSize, height: MenuBarIcon.canvasSize)
    let strip = CGSize(
      width: canvas.width + menuBarIconStripPadding * 2,
      height: canvas.height + menuBarIconStripPadding * 2)
    guard
      let context = CGContext(
        data: nil, width: Int(strip.width * scale), height: Int(strip.height * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(appearance.menuBarColor)
    context.fill(CGRect(origin: .zero, size: strip))
    context.translateBy(x: menuBarIconStripPadding, y: menuBarIconStripPadding)
    MenuBarIcon.draw(icon, in: context, color: appearance.menuBarTintColor)
    guard let cgImage = context.makeImage() else { return nil }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    bitmap.size = strip
    return bitmap.representation(using: .png, properties: [:])
  }

  private static func write(_ png: Data, to path: String) -> Never {
    do {
      try png.write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
      CommandLineOutput.fail("error: could not write \(path)")
    }
    exit(0)
  }

  @MainActor
  private static func settledHeight(of view: NSView, maxHeight: CGFloat) -> CGFloat {
    var height: CGFloat = 0
    var stableTurns = 0
    for _ in 0..<settleTurnLimit {
      view.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
      let measured = min(max(view.fittingSize.height, 1), maxHeight)
      if measured == height {
        stableTurns += 1
        if stableTurns >= stableTurnsNeeded { break }
      } else {
        height = measured
        stableTurns = 0
      }
    }
    return height
  }

  @MainActor
  private static func render(_ view: NSView, background: NSColor? = nil) -> Data? {
    let bounds = view.bounds
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
        pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)
    else { return nil }
    bitmap.size = bounds.size
    view.effectiveAppearance.performAsCurrentDrawingAppearance {
      if let background, let context = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.setFill()
        bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
      }
      view.cacheDisplay(in: bounds, to: bitmap)
    }
    return bitmap.representation(using: .png, properties: [:])
  }

  private enum Appearance: String {
    case light
    case dark

    var appearance: NSAppearance? {
      switch self {
      case .light: return NSAppearance(named: .aqua)
      case .dark: return NSAppearance(named: .darkAqua)
      }
    }

    var menuBarColor: CGColor {
      switch self {
      case .light: return CGColor(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255, alpha: 1)
      case .dark: return CGColor(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2B / 255, alpha: 1)
      }
    }

    var menuBarTintColor: CGColor {
      switch self {
      case .light: return CGColor(red: 0, green: 0, blue: 0, alpha: 1)
      case .dark: return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
      }
    }
  }

  private enum MenuBarIconState: String {
    case active
    case paused
    case quiet

    var icon: CompanionIcon {
      switch self {
      case .active: return .active
      case .paused: return .paused
      case .quiet: return .quiet
      }
    }
  }

  private struct MenuBarIconOptions {
    let icon: CompanionIcon
    let appearance: Appearance?
    let outputPath: String
  }

  private static func parseMenuBarIcon(_ arguments: [String]) -> MenuBarIconOptions? {
    var state: MenuBarIconState?
    var appearance: Appearance?
    var outputPath: String?
    var index = arguments.startIndex

    while index < arguments.count {
      switch arguments[index] {
      case menuBarIconFlag:
        index += 1
        guard index < arguments.count, let parsed = MenuBarIconState(rawValue: arguments[index])
        else { return nil }
        state = parsed
      case "--appearance":
        index += 1
        guard index < arguments.count, let parsed = Appearance(rawValue: arguments[index]) else {
          return nil
        }
        appearance = parsed
      case "-o":
        index += 1
        guard index < arguments.count else { return nil }
        outputPath = arguments[index]
      default:
        return nil
      }
      index += 1
    }

    guard let state, let outputPath else { return nil }
    return MenuBarIconOptions(icon: state.icon, appearance: appearance, outputPath: outputPath)
  }

  private enum RequestSource {
    case file(path: String, host: ApprovalCore.Host)
    case testPanel(TestPanelKind)

    var isTestPanel: Bool {
      guard case .testPanel = self else { return false }
      return true
    }
  }

  private struct Options {
    let source: RequestSource
    let outputPath: String
    let waitingCount: Int
    let appearance: Appearance?
    let accentColor: HexColor
    let isArmed: Bool
    let questionNotes: Bool
    let openMenu: PanelDropdownID?
    let checkpointLevel: ContextLevel?
  }

  private static func contextLevel(named name: String) -> ContextLevel? {
    switch name {
    case "soft": return .soft
    case "status": return .status
    case "insist": return .insist
    default: return nil
    }
  }

  private static func parse(_ arguments: [String]) -> Options? {
    var host: ApprovalCore.Host?
    var requestPath: String?
    var testPanelKind: TestPanelKind?
    var outputPath: String?
    var waitingCount = 0
    var appearance: Appearance?
    var accentColor = Settings.defaultAccentColor
    var isArmed = true
    var questionNotes = Settings.defaultQuestionNotes
    var openMenu: PanelDropdownID?
    var checkpointLevel: ContextLevel?
    var index = arguments.startIndex

    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--host":
        index += 1
        guard index < arguments.count,
          let parsedHost = ApprovalCore.Host(rawValue: arguments[index])
        else { return nil }
        host = parsedHost
      case "--test-panel":
        index += 1
        guard index < arguments.count, let kind = TestPanelKind(rawValue: arguments[index])
        else { return nil }
        testPanelKind = kind
      case "--waiting":
        index += 1
        guard index < arguments.count, let count = Int(arguments[index]), count >= 0 else {
          return nil
        }
        waitingCount = count
      case "--appearance":
        index += 1
        guard index < arguments.count, let parsed = Appearance(rawValue: arguments[index]) else {
          return nil
        }
        appearance = parsed
      case "--accent":
        index += 1
        guard index < arguments.count, let parsed = HexColor(hex: arguments[index]) else {
          return nil
        }
        accentColor = parsed
      case "--unarmed":
        isArmed = false
      case "--question-notes":
        questionNotes = true
      case "--open-menu":
        index += 1
        guard index < arguments.count, let menu = PanelDropdownID(rawValue: arguments[index])
        else { return nil }
        openMenu = menu
      case "--checkpoint-level":
        index += 1
        guard index < arguments.count, let level = contextLevel(named: arguments[index])
        else { return nil }
        checkpointLevel = level
      case "-o":
        index += 1
        guard index < arguments.count else { return nil }
        outputPath = arguments[index]
      default:
        guard !argument.hasPrefix("-"), requestPath == nil else { return nil }
        requestPath = argument
      }
      index += 1
    }

    guard let outputPath else { return nil }
    let source: RequestSource
    if let testPanelKind {
      guard host == nil, requestPath == nil else { return nil }
      source = .testPanel(testPanelKind)
    } else {
      guard let host, let requestPath else { return nil }
      source = .file(path: requestPath, host: host)
    }
    return Options(
      source: source, outputPath: outputPath, waitingCount: waitingCount,
      appearance: appearance, accentColor: accentColor, isArmed: isArmed,
      questionNotes: questionNotes, openMenu: openMenu, checkpointLevel: checkpointLevel)
  }

  private enum SnapshotStatus: String {
    case active
    case paused
    case pausedUntilOpen = "paused-until-open"
    case quiet

    var status: CountersignStatus {
      switch self {
      case .active: return .active
      case .paused: return .paused
      case .pausedUntilOpen: return .pausedUntilAppOpens
      case .quiet: return .quiet(until: Date().addingTimeInterval(quietSnapshotMinutes * 60))
      }
    }
  }

  private struct QuitPromptOptions {
    let outputPath: String
    let appearance: Appearance?
  }

  private static func parseQuitPrompt(_ arguments: [String]) -> QuitPromptOptions? {
    var outputPath: String?
    var appearance: Appearance?
    var index = arguments.startIndex

    while index < arguments.count {
      switch arguments[index] {
      case quitPromptFlag:
        break
      case "--appearance":
        index += 1
        guard index < arguments.count, let parsed = Appearance(rawValue: arguments[index]) else {
          return nil
        }
        appearance = parsed
      case "-o":
        index += 1
        guard index < arguments.count else { return nil }
        outputPath = arguments[index]
      default:
        return nil
      }
      index += 1
    }

    guard let outputPath else { return nil }
    return QuitPromptOptions(outputPath: outputPath, appearance: appearance)
  }

  private enum UpdateAnswerKind: String {
    case upToDate = "up-to-date"
    case available
    case failed

    var outcome: UpdateCheckOutcome {
      switch self {
      case .upToDate: return .upToDate
      case .available: return .newerAvailable(version: "0.2.0")
      case .failed: return .unknown(reason: "HTTP 404")
      }
    }
  }

  private struct UpdateAnswerOptions {
    let kind: UpdateAnswerKind
    let outputPath: String
    let appearance: Appearance?
  }

  private static func parseUpdateAnswer(_ arguments: [String]) -> UpdateAnswerOptions? {
    var kind: UpdateAnswerKind?
    var outputPath: String?
    var appearance: Appearance?
    var index = arguments.startIndex

    while index < arguments.count {
      switch arguments[index] {
      case updateAnswerFlag:
        index += 1
        guard index < arguments.count, let parsed = UpdateAnswerKind(rawValue: arguments[index])
        else { return nil }
        kind = parsed
      case "--appearance":
        index += 1
        guard index < arguments.count, let parsed = Appearance(rawValue: arguments[index]) else {
          return nil
        }
        appearance = parsed
      case "-o":
        index += 1
        guard index < arguments.count else { return nil }
        outputPath = arguments[index]
      default:
        return nil
      }
      index += 1
    }

    guard let kind, let outputPath else { return nil }
    return UpdateAnswerOptions(kind: kind, outputPath: outputPath, appearance: appearance)
  }

  private struct CornerCardOptions {
    let host: ApprovalCore.Host
    let project: String
    let offersGoThere: Bool
    let outputPath: String
    let appearance: Appearance?
  }

  private static func parseCornerCard(_ arguments: [String], flag: String) -> CornerCardOptions? {
    var host: ApprovalCore.Host?
    var project = waitingNoticeSampleProject
    var offersGoThere = true
    var outputPath: String?
    var appearance: Appearance?
    var index = arguments.startIndex

    while index < arguments.count {
      switch arguments[index] {
      case flag:
        index += 1
        guard index < arguments.count, let parsed = ApprovalCore.Host(rawValue: arguments[index])
        else { return nil }
        host = parsed
      case "--project":
        index += 1
        guard index < arguments.count, !arguments[index].isEmpty else { return nil }
        project = arguments[index]
      case "--no-app" where flag == waitingNoticeFlag:
        offersGoThere = false
      case "--appearance":
        index += 1
        guard index < arguments.count, let parsed = Appearance(rawValue: arguments[index]) else {
          return nil
        }
        appearance = parsed
      case "-o":
        index += 1
        guard index < arguments.count else { return nil }
        outputPath = arguments[index]
      default:
        return nil
      }
      index += 1
    }

    guard let host, let outputPath else { return nil }
    return CornerCardOptions(
      host: host, project: project, offersGoThere: offersGoThere, outputPath: outputPath,
      appearance: appearance)
  }

  private struct TourOptions {
    let step: FirstRunTourStep
    let outputPath: String
    let appearance: Appearance?
  }

  private static func parseTour(_ arguments: [String]) -> TourOptions? {
    var step: FirstRunTourStep?
    var outputPath: String?
    var appearance: Appearance?
    var index = arguments.startIndex

    while index < arguments.count {
      switch arguments[index] {
      case tourFlag:
        index += 1
        guard index < arguments.count, let raw = Int(arguments[index]),
          let parsed = FirstRunTourStep(rawValue: raw)
        else { return nil }
        step = parsed
      case "--appearance":
        index += 1
        guard index < arguments.count, let parsed = Appearance(rawValue: arguments[index]) else {
          return nil
        }
        appearance = parsed
      case "-o":
        index += 1
        guard index < arguments.count else { return nil }
        outputPath = arguments[index]
      default:
        return nil
      }
      index += 1
    }

    guard let outputPath, let step else { return nil }
    return TourOptions(step: step, outputPath: outputPath, appearance: appearance)
  }

  private struct SettingsOptions {
    let outputPath: String
    let appearance: Appearance?
    let disclosedHosts: [ApprovalCore.Host]
    let showsCopies: Bool
    let status: SnapshotStatus
    let home: URL?
    let size: CGSize?
    let pane: SettingsPane
    let restorePrompt: SettingsPane?
    let explanation: PreferenceName?
    let editorChoice: EditorChoice?
  }

  private static func parseSettings(_ arguments: [String]) -> SettingsOptions? {
    var outputPath: String?
    var appearance: Appearance?
    var disclosedHosts: [ApprovalCore.Host] = []
    var showsCopies = false
    var status = SnapshotStatus.active
    var home: URL?
    var size: CGSize?
    var pane = SettingsPane.standard
    var restorePrompt: SettingsPane?
    var explanation: PreferenceName?
    var editorChoice: EditorChoice?
    var index = arguments.startIndex

    while index < arguments.count {
      switch arguments[index] {
      case settingsFlag:
        break
      case "--home":
        index += 1
        guard index < arguments.count else { return nil }
        home = URL(fileURLWithPath: arguments[index], isDirectory: true)
      case "--show-changes":
        index += 1
        guard index < arguments.count, let host = ApprovalCore.Host(rawValue: arguments[index])
        else { return nil }
        disclosedHosts.append(host)
      case "--show-copies":
        showsCopies = true
      case "--status":
        index += 1
        guard index < arguments.count, let parsed = SnapshotStatus(rawValue: arguments[index])
        else { return nil }
        status = parsed
      case "--appearance":
        index += 1
        guard index < arguments.count, let parsed = Appearance(rawValue: arguments[index]) else {
          return nil
        }
        appearance = parsed
      case "--size":
        index += 1
        guard index < arguments.count, let parsed = parseSettingsSize(arguments[index]) else {
          return nil
        }
        size = parsed
      case "--tab":
        index += 1
        guard index < arguments.count, let parsed = SettingsPane(rawValue: arguments[index])
        else { return nil }
        pane = parsed
      case "--restore-prompt":
        index += 1
        guard index < arguments.count, let parsed = SettingsPane(rawValue: arguments[index]),
          parsed == .panels || parsed == .app
        else { return nil }
        restorePrompt = parsed
      case "--explanation":
        index += 1
        guard index < arguments.count, let parsed = PreferenceName(rawValue: arguments[index])
        else { return nil }
        explanation = parsed
      case "--editor-choice":
        index += 1
        guard index < arguments.count else { return nil }
        switch arguments[index] {
        case "ask":
          editorChoice = EditorChoice(origin: .advanced, missingBundleID: nil)
        case "missing":
          editorChoice = EditorChoice(origin: .advanced, missingBundleID: "com.example.Editor")
        default:
          return nil
        }
      case "-o":
        index += 1
        guard index < arguments.count else { return nil }
        outputPath = arguments[index]
      default:
        return nil
      }
      index += 1
    }

    guard let outputPath else { return nil }
    return SettingsOptions(
      outputPath: outputPath, appearance: appearance, disclosedHosts: disclosedHosts,
      showsCopies: showsCopies, status: status, home: home, size: size, pane: pane,
      restorePrompt: restorePrompt, explanation: explanation, editorChoice: editorChoice)
  }

  private static func parseSettingsSize(_ text: String) -> CGSize? {
    let parts = text.split(separator: "x", omittingEmptySubsequences: false)
    guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else {
      return nil
    }
    let size = CGSize(width: width, height: height)
    let minimum = SettingsWindowPlacement.minimumContentSize
    guard size.width >= minimum.width, size.height >= minimum.height else { return nil }
    return size
  }
}
