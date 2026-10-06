import Testing

@testable import ApprovalCore

@Suite struct DiffSummaryTests {
  @Test func countsAddedAndRemovedLinesWithoutHeaders() {
    let diff = """
      --- a/settings.json
      +++ b/settings.json
      @@ -1,4 +1,6 @@
       {
      -  "old": 1,
      +  "new": 1,
      +  "extra": 2,
      +  "more": 3,
       }
      """
    let summary = DiffSummary(unifiedDiff: diff)
    #expect(summary.added == 3)
    #expect(summary.removed == 1)
    #expect(summary.text == "3 lines added, 1 removed")
  }

  @Test func wordsSingularPluralAndEmpty() {
    #expect(DiffSummary(unifiedDiff: "+one\n").text == "1 line added")
    #expect(DiffSummary(unifiedDiff: "-one\n-two\n").text == "2 lines removed")
    #expect(DiffSummary(unifiedDiff: "").text == "no lines changed")
  }
}
