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

  @Test func countsLinesWhoseContentStartsWithDashesOrPlusesAcrossFiles() {
    let diff = """
      /tmp/first.sql
      --- a/first.sql
      +++ b/first.sql
      @@ -1,2 +1,3 @@
       select 1;
      --- old
      +++ new
      +select 2;
      --- a/second.sql
      +++ b/second.sql
      @@ -3 +3,2 @@
       select 3;
      +select 4;
      """
    let summary = DiffSummary(unifiedDiff: diff)
    #expect(summary.added == 3)
    #expect(summary.removed == 1)
    #expect(summary.text == "3 lines added, 1 removed")
  }

  @Test func wordsSingularPluralAndEmpty() {
    #expect(DiffSummary(unifiedDiff: "@@ -0,0 +1 @@\n+one\n").text == "1 line added")
    #expect(DiffSummary(unifiedDiff: "@@ -1,2 +0,0 @@\n-one\n-two\n").text == "2 lines removed")
    #expect(DiffSummary(unifiedDiff: "").text == "no lines changed")
  }
}
