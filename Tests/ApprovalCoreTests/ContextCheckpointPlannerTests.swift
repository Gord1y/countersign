import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointPlannerTests {
  private let now = Date(timeIntervalSince1970: 1_000)

  private func reading(_ tokens: Int) -> ContextReading {
    ContextReading(
      tokens: tokens, modelID: "claude-opus-5-5", hasMillionTokenWindow: false, compactionID: nil)
  }

  private func settings(mode: ContextCheckpointMode) -> ContextCheckpointSettings {
    var settings = ContextCheckpointSettings.default
    settings.enabled = true
    settings.mode = mode
    return settings
  }

  @Test(arguments: [true, false])
  func theStateRecordsTheReadingsWindow(million: Bool) {
    let reading = ContextReading(
      tokens: 50_000, modelID: "claude-opus-5-5", hasMillionTokenWindow: million,
      compactionID: nil)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading, previous: .fresh(now: now), settings: settings(mode: .silent),
      transcriptPath: "/t.jsonl", project: "shop-api", now: now)
    #expect(plan.state.hasMillionTokenWindow == million)
  }

  @Test func silentModeInjectsTheRenderedNoteOfTheCrossedLevel() {
    let settings = settings(mode: .silent)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(101_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: "/t.jsonl", project: "shop-api", now: now)

    let expected = ContextCheckpointNotes.render(
      settings.notes.soft, tokens: 101_000, handoffFile: settings.handoffFile, compactions: 0)
    #expect(plan.decision == .inject(expected))
    #expect(plan.state.fired == [.soft])
  }

  @Test func codexLadderFiresStatusAsAnInjectedNote() {
    let settings = ContextCheckpointSettings.default.forCodex(windowTokens: 258_400)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(160_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: "/t.jsonl", project: "shop-api", now: now)
    #expect(plan.state.fired.max() == .status)
    guard case .inject = plan.decision else {
      Issue.record("expected an injected note")
      return
    }
  }

  @Test func codexStopOnlyLevelsFireStopAt210000Tokens() {
    let settings = ContextCheckpointSettings.default.forCodex(windowTokens: 258_400)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(210_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: "/t.jsonl", project: "shop-api", now: now, levels: [.stop])
    #expect(plan.state.fired.max() == .stop)
    guard case .inject = plan.decision else {
      Issue.record("expected an injected note")
      return
    }
  }

  @Test func panelModeAsksWithTheLevelAndTheLadderUsed() {
    let settings = settings(mode: .panel)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(145_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: nil, project: "shop-api", now: now)

    let expected = ContextCheckpointPrompt(
      tokens: 145_000, level: .status, ladder: [100_000, 130_000, 160_000],
      modelID: "claude-opus-5-5", handoffFile: settings.handoffFile, notes: settings.notes,
      choices: [.handOff, .compactAfterStep, .continueWorking], compactions: 0, maxCompactions: 5)
    #expect(plan.decision == .panel(expected))
  }

  @Test func aPanelPromptCarriesTheCompactionCountAndTheLevelsChoices() {
    var previous = ContextCheckpointState.fresh(now: now)
    previous.compactions = 2
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(101_000), previous: previous, settings: settings(mode: .panel),
      transcriptPath: nil, project: "shop-api", now: now)

    guard case .panel(let prompt) = plan.decision else {
      Issue.record("expected a panel")
      return
    }
    #expect(prompt.choices == [.continueWorking, .compactAfterStep, .notThisSession])
    #expect(prompt.compactions == 2)
    #expect(prompt.maxCompactions == 5)
  }

  @Test func pastTheLimitThePanelNoLongerOffersCompact() {
    var previous = ContextCheckpointState.fresh(now: now)
    previous.compactions = 5
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(145_000), previous: previous, settings: settings(mode: .panel),
      transcriptPath: nil, project: "shop-api", now: now)

    guard case .panel(let prompt) = plan.decision else {
      Issue.record("expected a panel")
      return
    }
    #expect(prompt.choices == [.handOff, .continueWorking])
    #expect(!prompt.choices.contains(.compactAfterStep))
  }

  @Test func silentModePastTheLimitInjectsTheLimitNote() {
    var previous = ContextCheckpointState.fresh(now: now)
    previous.compactions = 5
    let settings = settings(mode: .silent)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(145_000), previous: previous, settings: settings,
      transcriptPath: nil, project: "shop-api", now: now)

    let expected = ContextCheckpointNotes.render(
      settings.notes.limit, tokens: 145_000, handoffFile: settings.handoffFile, compactions: 5)
    #expect(plan.decision == .inject(expected))
    #expect(expected.contains("compacted 5 times"))
    #expect(!expected.contains("{compactions}"))
  }

  @Test func silentModeBelowTheLimitKeepsTheLevelsNote() {
    var previous = ContextCheckpointState.fresh(now: now)
    previous.compactions = 4
    let settings = settings(mode: .silent)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(145_000), previous: previous, settings: settings,
      transcriptPath: nil, project: "shop-api", now: now)

    let expected = ContextCheckpointNotes.render(
      settings.notes.status, tokens: 145_000, handoffFile: settings.handoffFile, compactions: 4)
    #expect(plan.decision == .inject(expected))
  }

  @Test func stopInjectsItsRenderedNoteInPanelMode() {
    let settings = settings(mode: .panel)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(165_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: nil, project: "shop-api", now: now)

    let expected = ContextCheckpointNotes.render(
      settings.notes.stop, tokens: 165_000, handoffFile: settings.handoffFile, compactions: 0)
    #expect(plan.decision == .inject(expected))
    #expect(plan.state.fired == [.soft, .status, .insist, .stop])
  }

  @Test func stopInjectsItsRenderedNoteInSilentMode() {
    let settings = settings(mode: .silent)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(165_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: nil, project: "shop-api", now: now)

    let expected = ContextCheckpointNotes.render(
      settings.notes.stop, tokens: 165_000, handoffFile: settings.handoffFile, compactions: 0)
    #expect(plan.decision == .inject(expected))
  }

  @Test func stopOnlyLevelsInjectTheStopNoteInPanelModeAndFireEveryLevel() {
    let settings = settings(mode: .panel)
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(165_000), previous: .fresh(now: now), settings: settings,
      transcriptPath: nil, project: "shop-api", now: now, levels: [.stop])

    let expected = ContextCheckpointNotes.render(
      settings.notes.stop, tokens: 165_000, handoffFile: settings.handoffFile, compactions: 0)
    #expect(plan.decision == .inject(expected))
    #expect(plan.state.fired == [.soft, .status, .insist, .stop])
  }

  @Test func stopOnlyLevelsStayQuietBetweenInsistAndStop() {
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(145_000), previous: .fresh(now: now), settings: settings(mode: .panel),
      transcriptPath: nil, project: "shop-api", now: now, levels: [.stop])

    #expect(plan.decision == .nothing)
  }

  @Test func noCrossingKeepsTheStateCurrent() {
    let plan = ContextCheckpointPlanner.plan(
      reading: reading(50_000), previous: .fresh(now: Date(timeIntervalSince1970: 0)),
      settings: settings(mode: .panel), transcriptPath: "/t.jsonl", project: "shop-api",
      now: now)

    #expect(plan.decision == .nothing)
    #expect(plan.state.lastTokens == 50_000)
    #expect(plan.state.project == "shop-api")
    #expect(plan.state.transcriptPath == "/t.jsonl")
    #expect(plan.state.updatedAt == now)
  }
}
