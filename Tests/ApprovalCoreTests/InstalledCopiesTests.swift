import Foundation
import Testing

@testable import ApprovalCore

private struct InstallLayout {
  let base: URL

  var home: URL { base.appendingPathComponent("home") }
  var root: URL { base.appendingPathComponent("root") }
  var cli: String { home.appendingPathComponent(".local/bin/countersign").path }
  var userApp: String { home.appendingPathComponent("Applications/Countersign.app").path }
  var systemApp: String { root.appendingPathComponent("Applications/Countersign.app").path }

  init() throws {
    let created = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
    base = URL(fileURLWithPath: created.path).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: base)
  }

  func prefix(_ prefix: String) -> String {
    root.path + prefix
  }

  func keg(_ prefix: String = "/opt/homebrew", version: String) -> String {
    self.prefix(prefix) + "/Cellar/countersign/" + version
  }

  func writeFile(_ path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: url)
  }

  func link(_ path: String, to destination: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: destination)
  }

  func app(at path: String, version: String?) throws {
    try writeFile(path + "/Contents/MacOS/countersign")
    guard let version else { return }
    let plist = try PropertyListEncoder().encode(["CFBundleShortVersionString": version])
    try plist.write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
  }

  func homebrew(_ prefix: String = "/opt/homebrew", version: String, withApp: Bool = true)
    throws
  {
    let keg = keg(prefix, version: version)
    try writeFile(keg + "/bin/countersign")
    if withApp {
      try app(at: keg + "/Countersign.app", version: version)
    }
    try link(
      self.prefix(prefix) + "/opt/countersign", to: "../Cellar/countersign/" + version)
    try link(
      self.prefix(prefix) + "/bin/countersign",
      to: "../Cellar/countersign/" + version + "/bin/countersign")
  }

  func installer(appVersion: String? = "0.1.0", withApp: Bool = true) throws {
    try writeFile(cli)
    if withApp {
      try app(at: userApp, version: appVersion)
    }
  }

  func detect(cliVersion: (String) -> String? = { _ in nil }) -> [InstalledCopy] {
    InstalledCopies.detect(home: home, root: root, fileSystem: .local, cliVersion: cliVersion)
  }

  func duplicates(hooks: [String] = [], running: String? = nil) -> DuplicateInstall? {
    InstalledCopies.duplicates(
      home: home, root: root, fileSystem: .local, cliVersion: { _ in nil },
      hookExecutables: hooks, runningExecutable: running)
  }
}

@Suite struct InstalledCopiesTests {
  @Test func homebrewAloneIsOneCopyVersionedByItsKeg() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.1.0")
    let keg = layout.keg(version: "0.1.0")
    #expect(
      layout.detect() == [
        InstalledCopy(
          source: .homebrew(prefix: "/opt/homebrew"), appVersion: "0.1.0", cliVersion: "0.1.0",
          paths: [layout.prefix("/opt/homebrew") + "/bin/countersign", keg],
          executables: [
            keg + "/bin/countersign", keg + "/Countersign.app/Contents/MacOS/countersign",
          ],
          removals: [.brewUninstall(prefix: "/opt/homebrew")], hasApp: true,
          cliPath: layout.prefix("/opt/homebrew") + "/bin/countersign", appCopyVersion: nil)
      ])
    #expect(layout.duplicates() == nil)
  }

  @Test func theInstallerAloneIsOneCopyVersionedByItsApp() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: "0.1.0")
    #expect(
      layout.detect(cliVersion: { _ in "9.9.9" }) == [
        InstalledCopy(
          source: .installer, appVersion: "0.1.0", cliVersion: "9.9.9",
          paths: [layout.cli, layout.userApp],
          executables: [layout.cli, layout.userApp + "/Contents/MacOS/countersign"],
          removals: [.remove(layout.cli), .removeDirectory(layout.userApp)], hasApp: true,
          cliPath: layout.cli, appCopyVersion: nil)
      ])
    #expect(layout.detect(cliVersion: { _ in "9.9.9" }).map(\.version) == ["0.1.0"])
    #expect(layout.duplicates() == nil)
  }

  @Test func anInstallerWithoutItsAppAsksTheCLIForItsVersion() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(withApp: false)
    var asked: [String] = []
    let copies = layout.detect(cliVersion: {
      asked.append($0)
      return "0.0.9"
    })
    #expect(asked == [layout.cli])
    #expect(copies.map(\.version) == ["0.0.9"])
    #expect(copies.map(\.hasApp) == [false])
    #expect(copies.map(\.paths) == [[layout.cli]])
    #expect(copies.map(\.removals) == [[.remove(layout.cli)]])
  }

  @Test func anInstallerAppWithoutAVersionFallsBackToTheCLI() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: nil)
    #expect(layout.detect(cliVersion: { _ in "0.0.8" }).map(\.version) == ["0.0.8"])
    #expect(layout.detect().map(\.label) == ["Installer (version unknown)"])
  }

  @Test func homebrewAndTheInstallerAreTwoCopies() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    let duplicates = try #require(layout.duplicates())
    #expect(duplicates.title == "Two copies of Countersign are installed")
    #expect(
      duplicates.entries.map(\.label) == ["Homebrew 0.2.0", "Installer 0.1.0"])
    #expect(
      duplicates.entries.map(\.paths) == [
        ["/opt/homebrew/bin/countersign", "/opt/homebrew/Cellar/countersign/0.2.0"],
        ["~/.local/bin/countersign", "~/Applications/Countersign.app"],
      ])
    #expect(
      duplicates.entries.map(\.removalCommand) == [
        "brew uninstall countersign",
        "rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app",
      ])
    #expect(
      duplicates.entries.map(\.setupCommand) == [
        "/opt/homebrew/bin/countersign setup --cli --yes",
        "~/.local/bin/countersign setup --cli --yes",
      ])
  }

  @Test func homebrewTheInstallerAndApplicationsAreThreeCopies() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    try layout.app(at: layout.systemApp, version: "0.3.0")
    let duplicates = try #require(
      layout.duplicates(hooks: [layout.prefix("/opt/homebrew") + "/bin/countersign"]))
    #expect(duplicates.title == "Three copies of Countersign are installed")
    #expect(duplicates.entries.last?.label == "Countersign.app 0.3.0")
    #expect(duplicates.entries.last?.paths == ["/Applications/Countersign.app"])
    #expect(
      duplicates.steps(keeping: 0) == [
        DuplicateInstallStep(
          text: "Remove the others:",
          command:
            "rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app && rm -rf /Applications/Countersign.app"
        )
      ])
    #expect(duplicates.steps(keeping: 3).isEmpty)
  }

  @Test func theSettingsLinkIntoTheKegBelongsToHomebrew() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.link(
      layout.userApp, to: layout.prefix("/opt/homebrew") + "/opt/countersign/Countersign.app")
    let copies = layout.detect()
    #expect(copies.count == 1)
    #expect(copies.first?.paths.last == layout.userApp)
    #expect(
      copies.first?.removals == [
        .brewUninstall(prefix: "/opt/homebrew"), .remove(layout.userApp),
      ])

    try layout.writeFile(layout.cli)
    let duplicates = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(duplicates.entries.map(\.paths.count) == [3, 1])
    #expect(
      duplicates.entries.first?.removalCommand
        == "brew uninstall countersign && rm ~/Applications/Countersign.app")
  }

  @Test func danglingLinksAreNotCopies() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.link(
      layout.prefix("/opt/homebrew") + "/bin/countersign",
      to: "../Cellar/countersign/0.0.1/bin/countersign")
    try layout.link(layout.userApp, to: layout.keg(version: "0.0.1") + "/Countersign.app")
    try layout.link(layout.systemApp, to: layout.base.appendingPathComponent("gone").path)
    #expect(layout.detect().isEmpty)

    try layout.writeFile(layout.cli)
    #expect(layout.detect().map(\.source) == [.installer])
    #expect(layout.detect().map(\.paths) == [[layout.cli]])
  }

  @Test func aLinkedCLIIsNotAnInstallerCopy() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.link(layout.cli, to: layout.prefix("/opt/homebrew") + "/bin/countersign")
    #expect(layout.detect().map(\.source) == [.homebrew(prefix: "/opt/homebrew")])
  }

  @Test func anOldCellarVersionFolderIsNotACopy() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.writeFile(layout.keg(version: "0.0.9") + "/bin/countersign")
    try layout.app(at: layout.keg(version: "0.0.9") + "/Countersign.app", version: "0.0.9")
    try layout.homebrew(version: "0.1.0")
    let copies = layout.detect()
    #expect(copies.count == 1)
    #expect(copies.first?.version == "0.1.0")
  }

  @Test func theSameResolvedAppCountsOnce() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: "0.1.0")
    try layout.link(
      layout.root.appendingPathComponent("Applications").path,
      to: layout.home.appendingPathComponent("Applications").path)
    #expect(layout.detect().map(\.source) == [.installer])
  }

  @Test func anAppInHomeApplicationsWithoutTheCLIStandsAlone() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.app(at: layout.userApp, version: "0.1.0")
    try layout.app(at: layout.systemApp, version: nil)
    let duplicates = try #require(layout.duplicates())
    #expect(
      duplicates.entries.map(\.label) == [
        "Countersign.app (version unknown)", "Countersign.app 0.1.0",
      ])
    #expect(
      duplicates.entries.map(\.removalCommand) == [
        "rm -rf /Applications/Countersign.app", "rm -rf ~/Applications/Countersign.app",
      ])
  }

  @Test func twoHomebrewPrefixesNameTheirOwnBrew() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew("/opt/homebrew", version: "0.2.0")
    try layout.homebrew("/usr/local", version: "0.1.0", withApp: false)
    let duplicates = try #require(layout.duplicates())
    #expect(
      duplicates.entries.map(\.removalCommand) == [
        "/opt/homebrew/bin/brew uninstall countersign",
        "/usr/local/bin/brew uninstall countersign",
      ])
    #expect(
      duplicates.entries.last?.paths == [
        "/usr/local/bin/countersign", "/usr/local/Cellar/countersign/0.1.0",
      ])
  }

  @Test func marksTheCopyTheHooksCallAndTheRunningOne() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    let homebrewLink = layout.prefix("/opt/homebrew") + "/bin/countersign"
    let homebrewBinary = layout.keg(version: "0.2.0") + "/bin/countersign"
    let installerApp = layout.userApp + "/Contents/MacOS/countersign"

    for hooks in [[homebrewLink], [homebrewBinary], [homebrewLink, homebrewBinary]] {
      let duplicates = try #require(layout.duplicates(hooks: hooks, running: layout.cli))
      #expect(duplicates.entries.map(\.isCalledByHooks) == [true, false])
      #expect(duplicates.entries.map(\.isRunning) == [false, true])
    }

    for hooks in [[layout.cli], [installerApp], [layout.cli, "/elsewhere/countersign"]] {
      let duplicates = try #require(layout.duplicates(hooks: hooks, running: homebrewBinary))
      #expect(duplicates.entries.map(\.isCalledByHooks) == [false, true])
      #expect(duplicates.entries.map(\.isRunning) == [true, false])
    }
  }

  @Test func knowsWhenTheHooksCallNoCopy() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    let duplicates = try #require(
      layout.duplicates(hooks: ["/elsewhere/countersign"], running: layout.cli))
    #expect(duplicates.hooksCallNone)

    let disagreeing = try #require(
      layout.duplicates(
        hooks: [layout.cli, layout.prefix("/opt/homebrew") + "/bin/countersign"],
        running: layout.keg(version: "0.2.0") + "/bin/countersign"))
    #expect(disagreeing.entries.map(\.isCalledByHooks) == [true, true])
    #expect(!disagreeing.hooksCallNone)
  }

  @Test func suggestsTheNewestCopy() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: "0.1.0")
    try layout.app(at: layout.systemApp, version: "0.2.0")
    let duplicates = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(duplicates.entries.map(\.version) == ["0.1.0", "0.2.0"])
    #expect(duplicates.entries.map(\.isNewest) == [false, true])
    #expect(duplicates.suggestedIndex == 1)
  }

  @Test func equalVersionsSuggestTheCopyTheHooksCall() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.2.0")
    let onInstaller = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(onInstaller.suggestedIndex == 1)
    let onHomebrew = try #require(
      layout.duplicates(
        hooks: [layout.prefix("/opt/homebrew") + "/bin/countersign"], running: layout.cli))
    #expect(onHomebrew.suggestedIndex == 0)
  }

  @Test func equalVersionsWithoutTheHooksSuggestTheAppThenTheRunningCopy() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0", withApp: false)
    try layout.installer(appVersion: "0.2.0")
    let homebrewBinary = layout.keg(version: "0.2.0") + "/bin/countersign"
    let withoutApp = try #require(layout.duplicates(running: homebrewBinary))
    #expect(withoutApp.entries.map(\.hasApp) == [false, true])
    #expect(withoutApp.suggestedIndex == 1)

    try layout.app(at: layout.keg(version: "0.2.0") + "/Countersign.app", version: "0.2.0")
    let runningHomebrew = try #require(layout.duplicates(running: homebrewBinary))
    #expect(runningHomebrew.entries.map(\.hasApp) == [true, true])
    #expect(runningHomebrew.suggestedIndex == 0)
    #expect(try #require(layout.duplicates(running: layout.cli)).suggestedIndex == 1)
  }

  @Test func equalVersionsMakeNoCopyNewest() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.2.0")
    let duplicates = try #require(layout.duplicates())
    #expect(duplicates.entries.map(\.isNewest) == [false, false])
    #expect(duplicates.suggestedIndex == 0)
    #expect(!duplicates.doctorLine.detail.contains("newest"))
    #expect(!duplicates.agentPrompt.contains("newest"))
    let onInstaller = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(onInstaller.entries.map(\.isNewest) == [false, false])
    #expect(onInstaller.suggestedIndex == 1)
  }

  @Test func aHomebrewRevisionComparesAsItsVersion() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0_1")
    try layout.installer(appVersion: "0.1.0")
    let duplicates = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(duplicates.entries.map(\.label) == ["Homebrew 0.2.0_1", "Installer 0.1.0"])
    #expect(duplicates.entries.map(\.isNewest) == [true, false])
    #expect(duplicates.suggestedIndex == 0)
  }

  @Test func anUnknownVersionIsNeverNewest() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    try layout.app(at: layout.systemApp, version: nil)
    let appExecutable = layout.systemApp + "/Contents/MacOS/countersign"
    let duplicates = try #require(layout.duplicates(hooks: [appExecutable]))
    #expect(duplicates.entries.map(\.isNewest) == [true, false, false])
    #expect(duplicates.suggestedIndex == 0)

    let unknown = try InstallLayout()
    defer { unknown.remove() }
    try unknown.installer(appVersion: nil)
    try unknown.app(at: unknown.systemApp, version: nil)
    let noneKnown = try #require(
      unknown.duplicates(hooks: [unknown.systemApp + "/Contents/MacOS/countersign"]))
    #expect(noneKnown.entries.map(\.isNewest) == [false, false])
    #expect(noneKnown.suggestedIndex == 1)
  }

  @Test func stepsForACommandLineCopyTheHooksDoNotCall() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    let duplicates = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(
      duplicates.steps(keeping: 0) == [
        DuplicateInstallStep(
          text: "Point your agents' hooks at it:",
          command: "/opt/homebrew/bin/countersign setup --cli --yes"),
        DuplicateInstallStep(
          text: "Then remove the other:",
          command: "rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app"),
      ])
  }

  @Test func stepsForTheCopyTheHooksCall() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    let duplicates = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(
      duplicates.steps(keeping: 1) == [
        DuplicateInstallStep(text: "Remove the other:", command: "brew uninstall countersign")
      ])
  }

  @Test func stepsForAnAppTheHooksDoNotCall() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: "0.1.0")
    try layout.app(at: layout.systemApp, version: "0.2.0")
    let removal = DuplicateInstallStep(
      text: "Remove the other:",
      command: "rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app")
    let duplicates = try #require(layout.duplicates(hooks: [layout.cli]))
    #expect(
      duplicates.entries.map(\.setupCommand) == [
        "~/.local/bin/countersign setup --cli --yes", nil,
      ])
    #expect(
      duplicates.steps(keeping: 1) == [
        removal,
        DuplicateInstallStep(
          text:
            "Then open /Applications/Countersign.app and click Update on each agent under Agents, so the hooks call this copy.",
          command: nil),
      ])

    let called = try #require(
      layout.duplicates(hooks: [layout.systemApp + "/Contents/MacOS/countersign"]))
    #expect(called.steps(keeping: 1) == [removal])
  }

  @Test func thePromptForAnAgentDescribesEveryCopy() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: "0.1.0")
    try layout.app(at: layout.systemApp, version: "0.2.0")
    let appExecutable = layout.systemApp + "/Contents/MacOS/countersign"
    let duplicates = try #require(
      layout.duplicates(hooks: [layout.cli], running: appExecutable))
    #expect(
      duplicates.agentPrompt == """
        I have two copies of Countersign installed (a macOS approval panel for AI coding agents):
        - Installer 0.1.0: ~/.local/bin/countersign, ~/Applications/Countersign.app (the hooks call this one)
        - Countersign.app 0.2.0: /Applications/Countersign.app (running now, newest)
        Each copy updates on its own, and my agents' hooks call only one of them. Help me choose which one to keep: explain the options and their trade-offs, then give me the exact commands. Don't delete or change anything without asking me first.
        Background: https://github.com/Gord1y/countersign/blob/main/docs/troubleshooting.md#two-copies-of-countersign-are-installed
        """)
    #expect(
      try #require(layout.duplicates()).agentPrompt.contains(
        "my agents' hooks call none of them."))
    #expect(
      try #require(layout.duplicates(hooks: [layout.cli, appExecutable])).agentPrompt.contains(
        "my agents' hooks call more than one of them."))
  }

  @Test func theDoctorLineListsTheCommandThatRemovesEachCopy() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    let duplicates = try #require(layout.duplicates(running: "/src/.build/debug/countersign"))
    #expect(
      duplicates.doctorLine.text
        == "warn copies: 2 copies of Countersign are installed; Homebrew 0.2.0: /opt/homebrew/bin/countersign, /opt/homebrew/Cellar/countersign/0.2.0 (newest); Installer 0.1.0: ~/.local/bin/countersign, ~/Applications/Countersign.app; the hooks call none of them; keep the one you want and remove the other; the command that removes each: Homebrew 0.2.0: brew uninstall countersign, Installer 0.1.0: rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app; countersign settings shows the steps for the copy you pick"
    )
  }

  @Test func theDoctorLineNeverNamesACopyToKeep() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: "0.1.0")
    try layout.app(at: layout.systemApp, version: "0.2.0")
    let duplicates = try #require(
      layout.duplicates(
        hooks: [layout.cli], running: layout.systemApp + "/Contents/MacOS/countersign"))
    #expect(
      duplicates.doctorLine
        == DoctorLine(
          status: .warn, check: "copies",
          detail:
            "2 copies of Countersign are installed; Installer 0.1.0: ~/.local/bin/countersign, ~/Applications/Countersign.app (called by the hooks); Countersign.app 0.2.0: /Applications/Countersign.app (running now, newest); keep the one you want and remove the other; the command that removes each: Installer 0.1.0: rm ~/.local/bin/countersign && rm -rf ~/Applications/Countersign.app, Countersign.app 0.2.0: rm -rf /Applications/Countersign.app; countersign settings shows the steps for the copy you pick"
        ))
    #expect(!duplicates.doctorLine.detail.contains("keep Installer"))
    #expect(!duplicates.doctorLine.detail.contains("keep Countersign.app"))
  }

  @Test func flagsAnInstallerAppAndCommandOnDifferentVersions() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.installer(appVersion: "0.1.0")
    let mismatch = { (cli: String?) in
      InstalledCopies.versionMismatch(
        home: layout.home, root: layout.root, fileSystem: .local, cliVersion: { _ in cli })
    }
    let appOlder = try #require(mismatch("0.2.0"))
    #expect(appOlder.title == "The menu-bar app is older than the command-line tool")
    #expect(
      appOlder.advice == "Countersign.app is 0.1.0 but countersign is 0.2.0. Update the app:")
    #expect(
      appOlder.command
        == "curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | COUNTERSIGN_APP=1 sh"
    )
    #expect(
      appOlder.doctorLine.text
        == "warn versions: the menu-bar app is older than the command-line tool: Countersign.app is 0.1.0 but countersign is 0.2.0. Update the app: curl -fsSL https://raw.githubusercontent.com/Gord1y/countersign/main/install.sh | COUNTERSIGN_APP=1 sh"
    )

    let cliOlder = try #require(mismatch("0.0.9"))
    #expect(cliOlder.title == "The command-line tool is older than the menu-bar app")
    #expect(
      cliOlder.advice
        == "countersign is 0.0.9 but Countersign.app is 0.1.0, and your agents' hooks run countersign. Update it:"
    )
    #expect(cliOlder.command == UpdateCommand.curlInstallCommand)

    #expect(mismatch("0.1.0") == nil)
    #expect(mismatch(nil) == nil)

    let withoutApp = try InstallLayout()
    defer { withoutApp.remove() }
    try withoutApp.installer(withApp: false)
    #expect(
      InstalledCopies.versionMismatch(
        home: withoutApp.home, root: withoutApp.root, fileSystem: .local,
        cliVersion: { _ in "0.2.0" }) == nil)
  }

  @Test func aRealCopyAtHomebrewsVersionBelongsToHomebrew() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.3.0")
    try layout.app(at: layout.userApp, version: "0.3.0")
    let copies = layout.detect()
    #expect(copies.map(\.source) == [.homebrew(prefix: "/opt/homebrew")])
    #expect(copies.first?.paths.contains(layout.userApp) == true)
    #expect(copies.first?.removals.contains(.removeDirectory(layout.userApp)) == true)
    #expect(copies.first?.appCopyVersion == "0.3.0")
    #expect(layout.duplicates() == nil)
  }

  @Test func anOlderRealCopyIsOnlyAVersionMismatch() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.3.0")
    try layout.app(at: layout.userApp, version: "0.2.0")
    #expect(layout.detect().map(\.source) == [.homebrew(prefix: "/opt/homebrew")])
    let mismatch = try #require(
      InstalledCopies.versionMismatch(
        home: layout.home, root: layout.root, fileSystem: .local, cliVersion: { _ in nil }))
    #expect(
      mismatch.title == "The copy of Countersign.app in ~/Applications is older than Homebrew's")
    #expect(
      mismatch.advice
        == "Countersign.app in ~/Applications is 0.2.0 but Homebrew installed 0.3.0. The menu-bar app updates its copy when it starts; to update it now, open Settings ▸ App:"
    )
    #expect(mismatch.command == "countersign settings")
  }

  @Test func aNewerRealCopyStaysASecondInstall() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.3.0")
    try layout.app(at: layout.userApp, version: "0.4.0")
    #expect(layout.detect().map(\.source) == [.homebrew(prefix: "/opt/homebrew"), .app])
    #expect(layout.detect().first?.appCopyVersion == nil)
  }

  @Test func aRealCopyBesideTheInstallerCLIStaysTheInstallers() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.3.0")
    try layout.installer(appVersion: "0.3.0")
    let copies = layout.detect()
    #expect(copies.map(\.source) == [.homebrew(prefix: "/opt/homebrew"), .installer])
    #expect(copies.first?.appCopyVersion == nil)
    #expect(copies.last?.paths == [layout.cli, layout.userApp])
  }

  @Test func theKegFolderRevisionDoesNotMakeTheCopyOlder() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.3.0_1")
    try layout.app(at: layout.keg(version: "0.3.0_1") + "/Countersign.app", version: "0.3.0")
    try layout.app(at: layout.userApp, version: "0.3.0")
    #expect(layout.detect().map(\.source) == [.homebrew(prefix: "/opt/homebrew")])
    #expect(
      InstalledCopies.versionMismatch(
        home: layout.home, root: layout.root, fileSystem: .local, cliVersion: { _ in nil })
        == nil)
  }

  @Test func doctorPrintsTheLinesRightAfterTheVersion() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    try layout.homebrew(version: "0.2.0")
    try layout.installer(appVersion: "0.1.0")
    var input = Doctor.Input(
      version: "0.2.0", resolvedExecutablePath: layout.cli, stableExecutablePath: layout.cli,
      hosts: [], configPath: "/config.json", configFileExists: false, configLogLines: [],
      queueDirectoryPath: "/queue", liveTicketCount: 0, pauseState: .active,
      quietUntilDescription: nil, logFilePath: "/log", logFileSize: nil)
    #expect(!Doctor.report(input).contains { $0.check == "copies" })
    let duplicates = try #require(layout.duplicates(running: layout.cli))
    input.duplicateInstall = duplicates
    let lines = Doctor.report(input)
    #expect(lines.map(\.check).prefix(2) == ["version", "copies"])
    #expect(lines[1] == duplicates.doctorLine)
    #expect(Doctor.exitCode(for: lines) == 0)

    let mismatch = try #require(InstallVersionMismatch(appVersion: "0.1.0", cliVersion: "0.2.0"))
    input.installVersionMismatch = mismatch
    let withMismatch = Doctor.report(input)
    #expect(withMismatch.map(\.check).prefix(3) == ["version", "copies", "versions"])
    #expect(withMismatch[2] == mismatch.doctorLine)
    #expect(Doctor.exitCode(for: withMismatch) == 0)
  }

  @Test func anEntryMarksHooksRunningAndNewest() {
    let entry = DuplicateInstallEntry(
      label: "Installer 0.1.0", version: "0.1.0", paths: ["~/.local/bin/countersign"],
      isCalledByHooks: true, isRunning: true, isNewest: true, hasApp: false,
      removalCommand: "rm ~/.local/bin/countersign",
      setupCommand: "~/.local/bin/countersign setup --cli --yes")
    #expect(
      entry.summary
        == "Installer 0.1.0: ~/.local/bin/countersign (called by the hooks, running now, newest)")
    #expect(
      entry.promptLine
        == "- Installer 0.1.0: ~/.local/bin/countersign (the hooks call this one, running now, newest)"
    )
  }

  @Test func countsAreSpelledOutUpToFour() {
    #expect(DuplicateInstall.countWord(2) == "Two")
    #expect(DuplicateInstall.countWord(3) == "Three")
    #expect(DuplicateInstall.countWord(4) == "Four")
    #expect(DuplicateInstall.countWord(5) == "5")
  }

  @Test func readsTheVersionFromVersionOutput() {
    #expect(InstalledCopies.version(fromVersionOutput: "countersign 0.1.0\n") == "0.1.0")
    #expect(InstalledCopies.version(fromVersionOutput: "  countersign 0.2.0_1  ") == "0.2.0_1")
    #expect(InstalledCopies.version(fromVersionOutput: "other 0.1.0") == nil)
    #expect(InstalledCopies.version(fromVersionOutput: "countersign ") == nil)
    #expect(InstalledCopies.version(fromVersionOutput: "countersign 0.1 beta") == nil)
    #expect(InstalledCopies.version(fromVersionOutput: "") == nil)
  }

  @Test func readsTheVersionFromTheKegFolder() {
    #expect(InstalledCopies.kegVersion("/opt/homebrew/Cellar/countersign/0.2.0_1") == "0.2.0_1")
    #expect(InstalledCopies.kegVersion("/opt/homebrew/opt/countersign") == nil)
    #expect(InstalledCopies.kegVersion("/opt/homebrew/Cellar/other/0.1.0") == nil)
  }

  @Test func showsPathsUnderTheRootAsAbsoluteAndTheHomeWithATilde() {
    let home = URL(fileURLWithPath: "/Users/dev")
    let root = URL(fileURLWithPath: "/Users/dev/demo/root")
    let system = URL(fileURLWithPath: "/")
    #expect(
      InstalledCopies.shown(
        "/Users/dev/demo/root/Applications/Countersign.app", home: home, root: root)
        == "/Applications/Countersign.app")
    #expect(
      InstalledCopies.shown("/Users/dev/.local/bin/countersign", home: home, root: root)
        == "~/.local/bin/countersign")
    #expect(
      InstalledCopies.shown("/Applications/Countersign.app", home: home, root: system)
        == "/Applications/Countersign.app")
    #expect(
      InstalledCopies.shown("/Users/dev/Applications/Countersign.app", home: home, root: system)
        == "~/Applications/Countersign.app")
  }

  @Test func quotesAPathOnlyWhenTheShellNeedsIt() {
    #expect(InstalledCopies.shellPath("~/.local/bin/countersign") == "~/.local/bin/countersign")
    #expect(InstalledCopies.shellPath("~/My Apps/Countersign.app") == "~/'My Apps/Countersign.app'")
    #expect(
      InstalledCopies.shellPath("/Volumes/My Disk/Countersign.app")
        == "'/Volumes/My Disk/Countersign.app'")
    #expect(
      InstalledCopies.command(
        for: .removeDirectory("/Users/dev/My Apps/Countersign.app"), qualifiesBrew: false,
        home: URL(fileURLWithPath: "/Users/dev"), root: URL(fileURLWithPath: "/"))
        == "rm -rf ~/'My Apps/Countersign.app'")
  }

  @Test func namesEachSource() {
    #expect(InstallSource.homebrew(prefix: "/usr/local").name == "Homebrew")
    #expect(InstallSource.installer.name == "Installer")
    #expect(InstallSource.app.name == "Countersign.app")
    #expect(InstallSource.homebrew(prefix: "/opt/homebrew").isHomebrew)
    #expect(!InstallSource.installer.isHomebrew)
    #expect(!InstallSource.app.isHomebrew)
  }

  @Test func theLocalFileSystemReadsKindsLinksAndContents() throws {
    let layout = try InstallLayout()
    defer { layout.remove() }
    let file = layout.base.appendingPathComponent("file").path
    let directory = layout.base.appendingPathComponent("directory").path
    let link = layout.base.appendingPathComponent("link").path
    let dangling = layout.base.appendingPathComponent("dangling").path
    let fifo = layout.base.appendingPathComponent("fifo").path
    let missing = layout.base.appendingPathComponent("missing").path
    try layout.writeFile(file)
    try FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true)
    try layout.link(link, to: "file")
    try layout.link(dangling, to: "missing")
    #expect(mkfifo(fifo, 0o600) == 0)

    let local = InstallFileSystem.local
    #expect(local.kind(file) == .file)
    #expect(local.kind(directory) == .directory)
    #expect(local.kind(link) == .symbolicLink)
    #expect(local.kind(dangling) == .symbolicLink)
    #expect(local.kind(fifo) == nil)
    #expect(local.kind(missing) == nil)
    #expect(local.resolved(link) == file)
    #expect(local.resolved(file) == file)
    #expect(local.resolved(dangling) == nil)
    #expect(local.resolved(missing) == nil)
    #expect(local.contents(link) == Data("#!/bin/sh\n".utf8))
    #expect(local.contents(missing) == nil)
  }
}
