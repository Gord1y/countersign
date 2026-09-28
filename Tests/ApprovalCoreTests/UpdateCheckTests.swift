import Foundation
import Testing

@testable import ApprovalCore

@Suite struct UpdateCheckTests {
  private func data(_ json: String) -> Data {
    Data(json.utf8)
  }

  @Test func evaluateReportsANewerRelease() {
    let outcome = UpdateCheck.evaluate(
      indexData: data(#"{"schemaVersion": 1, "releases": [{"version": "0.2.0"}]}"#),
      currentVersion: "0.1.0")

    #expect(outcome == .newerAvailable(version: "0.2.0"))
  }

  @Test func evaluateReportsUpToDateForAnEqualVersion() {
    let outcome = UpdateCheck.evaluate(
      indexData: data(#"{"schemaVersion": 1, "releases": [{"version": "0.1.0"}]}"#),
      currentVersion: "0.1.0")

    #expect(outcome == .upToDate)
  }

  @Test func evaluateReportsUpToDateForAnOlderVersion() {
    let outcome = UpdateCheck.evaluate(
      indexData: data(#"{"schemaVersion": 1, "releases": [{"version": "0.1.0"}]}"#),
      currentVersion: "0.2.0")

    #expect(outcome == .upToDate)
  }

  @Test func evaluateReportsUpToDateWithNoReleases() {
    let outcome = UpdateCheck.evaluate(
      indexData: data(#"{"schemaVersion": 1, "releases": []}"#), currentVersion: "0.1.0")

    #expect(outcome == .upToDate)
  }

  @Test func evaluateReportsUnknownForAMalformedIndex() {
    let outcome = UpdateCheck.evaluate(indexData: data("not json"), currentVersion: "0.1.0")

    guard case .unknown = outcome else {
      Issue.record("expected .unknown, got \(outcome)")
      return
    }
  }

  @Test func compareTreatsAHigherPatchAsNewer() {
    #expect(
      UpdateCheck.compare(current: "0.1.0", latest: "0.1.1") == .newerAvailable(version: "0.1.1"))
  }

  @Test func compareTreatsAHigherMinorAsNewerRegardlessOfPatch() {
    #expect(
      UpdateCheck.compare(current: "0.1.9", latest: "0.2.0") == .newerAvailable(version: "0.2.0"))
  }

  @Test func compareTreatsAHigherMajorAsNewer() {
    #expect(
      UpdateCheck.compare(current: "0.9.9", latest: "1.0.0") == .newerAvailable(version: "1.0.0"))
  }

  @Test func compareTreatsAnEqualVersionAsUpToDate() {
    #expect(UpdateCheck.compare(current: "0.1.0", latest: "0.1.0") == .upToDate)
  }

  @Test func compareTreatsAnOlderVersionAsUpToDate() {
    #expect(UpdateCheck.compare(current: "0.2.0", latest: "0.1.0") == .upToDate)
  }

  @Test func compareTreatsAGarbageCurrentVersionAsUnknown() {
    guard case .unknown = UpdateCheck.compare(current: "not-a-version", latest: "0.2.0") else {
      Issue.record("expected .unknown")
      return
    }
  }

  @Test func compareTreatsAGarbageLatestVersionAsUnknown() {
    guard case .unknown = UpdateCheck.compare(current: "0.1.0", latest: "beta") else {
      Issue.record("expected .unknown")
      return
    }
  }

  @Test func compareTreatsAPreReleaseSuffixAsUnknown() {
    guard case .unknown = UpdateCheck.compare(current: "0.1.0", latest: "0.2.0-beta.1") else {
      Issue.record("expected .unknown")
      return
    }
  }
}

@Suite struct UpdateCheckScheduleTests {
  @Test func isDueWithNoPriorAttempt() {
    #expect(UpdateCheckSchedule.isDue(lastAttempt: nil, now: Date()))
  }

  @Test func isNotDueBeforeTheIntervalElapses() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let lastAttempt = now.addingTimeInterval(-UpdateCheckSchedule.interval + 1)

    #expect(!UpdateCheckSchedule.isDue(lastAttempt: lastAttempt, now: now))
  }

  @Test func isDueOnceTheIntervalElapses() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let lastAttempt = now.addingTimeInterval(-UpdateCheckSchedule.interval)

    #expect(UpdateCheckSchedule.isDue(lastAttempt: lastAttempt, now: now))
  }

  @Test func isDueWhenTheClockMovesBackwards() {
    let lastAttempt = Date(timeIntervalSince1970: 2_000_000)
    let now = Date(timeIntervalSince1970: 1_000_000)

    #expect(UpdateCheckSchedule.isDue(lastAttempt: lastAttempt, now: now))
  }
}
