import Testing

@testable import ApprovalCore

@Suite struct ContextCheckpointChoicesTests {
  private let choices = ContextCheckpointChoices.default

  @Test func defaultsPerLevel() {
    #expect(choices.list(for: .soft) == [.continueWorking, .compactAfterStep, .notThisSession])
    #expect(choices.list(for: .status) == [.handOff, .compactAfterStep, .continueWorking])
    #expect(choices.list(for: .insist) == [.handOff, .compactAfterStep, .continueWorking])
  }

  @Test func stopOffersNothing() {
    #expect(choices.list(for: .stop).isEmpty)
    #expect(choices.offered(at: .stop, compactions: 0, maxCompactions: 5).isEmpty)
    #expect(choices.offered(at: .stop, compactions: 5, maxCompactions: 5).isEmpty)
  }

  @Test func compactIsOfferedBelowTheLimit() {
    #expect(
      choices.offered(at: .soft, compactions: 4, maxCompactions: 5)
        == [.continueWorking, .compactAfterStep, .notThisSession])
  }

  @Test(arguments: [5, 6, 50])
  func compactIsDroppedAtAndPastTheLimit(compactions: Int) {
    #expect(
      choices.offered(at: .soft, compactions: compactions, maxCompactions: 5)
        == [.continueWorking, .notThisSession])
    #expect(
      choices.offered(at: .status, compactions: compactions, maxCompactions: 5)
        == [.handOff, .continueWorking])
  }

  @Test func aZeroLimitNeverOffersCompact() {
    #expect(
      choices.offered(at: .status, compactions: 0, maxCompactions: 0)
        == [.handOff, .continueWorking])
  }

  @Test func anAllCompactListPastTheLimitFallsBackToHandOffAndContinue() {
    let onlyCompact = ContextCheckpointChoices(
      soft: [.compactAfterStep], status: [.compactAfterStep], insist: [.compactAfterStep])
    #expect(
      onlyCompact.offered(at: .soft, compactions: 5, maxCompactions: 5)
        == [.handOff, .continueWorking])
    #expect(
      onlyCompact.offered(at: .soft, compactions: 4, maxCompactions: 5) == [.compactAfterStep])
  }

  @Test func orderedPutsTheHighlightedFirstThenCanonicalOrder() {
    let all = Set(ContextCheckpointChoice.allCases)
    #expect(
      ContextCheckpointChoices.ordered(all, highlighted: .continueWorking)
        == [.continueWorking, .compactAfterStep, .handOff, .notThisSession])
    #expect(
      ContextCheckpointChoices.ordered([.notThisSession, .handOff], highlighted: .notThisSession)
        == [.notThisSession, .handOff])
    #expect(
      ContextCheckpointChoices.ordered([.notThisSession, .handOff], highlighted: .compactAfterStep)
        == [.handOff, .notThisSession])
  }

  @Test func configNamesRoundTripEveryCase() {
    for choice in ContextCheckpointChoice.allCases {
      #expect(ContextCheckpointChoice(configName: choice.configName) == choice)
    }
    #expect(
      ContextCheckpointChoice.allCases.map(\.configName) == [
        "continue", "compact", "handoff", "mute",
      ])
    #expect(ContextCheckpointChoice(configName: "later") == nil)
  }

  @Test func listTextsAreShort() {
    #expect(
      PreferenceReset.choicesText(choices.soft) == "Continue, Compact, Not this session")
    #expect(PreferenceReset.choicesText(choices.status) == "Hand off, Compact, Continue")
  }
}
