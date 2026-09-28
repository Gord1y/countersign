import Foundation
import Testing

@testable import ApprovalCore

@Suite struct StateSwitchesTests {
  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-stateswitches-\(UUID().uuidString)")
  }

  private func stateSwitches(in directory: URL) -> StateSwitches {
    StateSwitches(
      pauseSwitch: PauseSwitch(file: directory.appendingPathComponent("pause")),
      quietTime: QuietTime(file: directory.appendingPathComponent("quiet-until")))
  }

  @Test func pauseClearsQuietTime() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let switches = stateSwitches(in: directory)
    try switches.quietTime.quiet(until: Date().addingTimeInterval(300))

    try switches.pause()

    #expect(switches.pauseSwitch.isPaused)
    #expect(switches.quietTime.activeUntil() == nil)
  }

  @Test func pauseUntilAppOpensClearsQuietTimeAndReturnsTrue() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let switches = stateSwitches(in: directory)
    try switches.quietTime.quiet(until: Date().addingTimeInterval(300))

    let paused = try switches.pauseUntilAppOpens()

    #expect(paused)
    #expect(switches.pauseSwitch.state == .pausedUntilAppOpens)
    #expect(switches.quietTime.activeUntil() == nil)
  }

  @Test func pauseUntilAppOpensWhileAlreadyPausedReturnsFalseAndLeavesQuietTimeAsItWas() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let switches = stateSwitches(in: directory)
    try switches.pauseSwitch.pause()
    let until = Date().addingTimeInterval(300)
    try switches.quietTime.quiet(until: until)

    let paused = try switches.pauseUntilAppOpens()

    #expect(!paused)
    #expect(switches.pauseSwitch.state == .paused)
    let active = switches.quietTime.activeUntil()
    #expect(active != nil)
    #expect(abs((active ?? .distantPast).timeIntervalSince(until)) < 1)
  }

  @Test func snoozeWhilePausedThrowsAndWritesNothing() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let switches = stateSwitches(in: directory)
    try switches.pauseSwitch.pause()

    #expect(throws: SnoozeRefusal.paused) {
      try switches.snooze(until: Date().addingTimeInterval(300))
    }
    #expect(switches.quietTime.activeUntil() == nil)
  }

  @Test func snoozeWhileActiveSetsQuietTime() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let switches = stateSwitches(in: directory)
    let until = Date().addingTimeInterval(300)

    try switches.snooze(until: until)

    let active = switches.quietTime.activeUntil()
    #expect(active != nil)
    #expect(abs((active ?? .distantPast).timeIntervalSince(until)) < 1)
  }
}
