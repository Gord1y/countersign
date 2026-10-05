import Testing

@testable import ApprovalCore

@Suite struct PreferenceRulesContextTests {
  @Test func readsAThreeStepLadderInThousands() {
    #expect(
      PreferenceRules.contextLadder(fromThousands: "100, 130, 160")
        == .success([100_000, 130_000, 160_000]))
    #expect(
      PreferenceRules.contextLadder(fromThousands: "1 2 2000") == .success([1000, 2000, 2_000_000]))
  }

  @Test func rejectsALadderThatIsNotThreeAscendingWholeThousandsInRange() {
    let inputs = [
      "", "100, 130", "100, 130, 160, 190", "100, 100, 160", "160, 130, 100", "a, b, c",
      "1.5, 2, 3", "0, 1, 2", "1, 2, 2001",
    ]
    for input in inputs {
      #expect(PreferenceRules.contextLadder(fromThousands: input) == .failure(.ladder))
    }
    #expect(
      ContextTextError.ladder.description
        == "Enter three ascending numbers of thousands of tokens")
  }

  @Test func showsALadderInThousands() {
    #expect(PreferenceRules.contextLadderText([100_000, 130_000, 160_000]) == "100, 130, 160")
    #expect(PreferenceRules.contextLadderText([200_400, 300_600, 1_000_000]) == "200, 301, 1000")
  }

  @Test func checksAModelPrefix() {
    #expect(PreferenceRules.contextModelPrefix(" claude-opus-5 ") == .success("claude-opus-5"))
    #expect(
      ContextTextError.emptyPrefix.description
        == "Enter a model ID prefix, like claude-opus-5")
    #expect(PreferenceRules.contextModelPrefix("  ") == .failure(.emptyPrefix))
    #expect(
      PreferenceRules.contextModelPrefix("claude opus") == .failure(.prefixContainsWhitespace))
    #expect(!ContextTextError.emptyPrefix.description.isEmpty)
    #expect(!ContextTextError.prefixContainsWhitespace.description.isEmpty)
  }

  @Test func checksTheHandoffFile() {
    #expect(
      PreferenceRules.contextHandoffFile(" notes/handoff.md ") == .success("notes/handoff.md"))
    #expect(PreferenceRules.contextHandoffFile(" ") == .failure(.emptyHandoffFile))
    #expect(ContextTextError.emptyHandoffFile.description == "Enter a file path")
  }

  @Test func checksANote() {
    #expect(PreferenceRules.contextNote("Hello {tokens}\n") == .success("Hello {tokens}\n"))
    #expect(PreferenceRules.contextNote(" \n ") == .failure(.emptyNote))
    #expect(
      PreferenceRules.contextNote(String(repeating: "a", count: 4001)) == .failure(.noteTooLong))
    #expect(
      PreferenceRules.contextNote(String(repeating: "a", count: 4000))
        == .success(String(repeating: "a", count: 4000)))
    #expect(ContextTextError.emptyNote.description == "Enter the note")
    #expect(ContextTextError.noteTooLong.description == "A note is at most 4000 characters")
  }

  @Test func snapsTheRearmSliderToStepsOfFive() {
    #expect(PreferenceRules.contextRearmBelow(percent: 0) == 0.1)
    #expect(PreferenceRules.contextRearmBelow(percent: 100) == 0.95)
    #expect(PreferenceRules.contextRearmBelow(percent: 62) == 0.6)
    #expect(PreferenceRules.contextRearmBelow(percent: 63) == 0.65)
    #expect(PreferenceRules.contextRearmPercent(0.6) == 60)
    #expect(PreferenceRules.contextRearmPercent(0.62) == 60)
    #expect(PreferenceRules.contextRearmPercentRange == 10...95)
  }
}
