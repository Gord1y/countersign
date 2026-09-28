import Foundation
import Testing

@testable import ApprovalCore

@Suite struct ReleaseIndexTests {
  private func data(_ json: String) -> Data {
    Data(json.utf8)
  }

  private func isFailure(_ result: Result<String?, ReleaseIndexError>) -> Bool {
    guard case .failure = result else { return false }
    return true
  }

  @Test func returnsTheNewestVersionFromTheFirstEntry() {
    let result = ReleaseIndex.latestVersion(
      from: data(
        """
        {"schemaVersion": 1, "releases": [{"version": "0.2.0"}, {"version": "0.1.0"}]}
        """))

    #expect(result == .success("0.2.0"))
  }

  @Test func ignoresUnknownFieldsOnEachRelease() {
    let result = ReleaseIndex.latestVersion(
      from: data(
        """
        {"schemaVersion": 1, "releases": [{"version": "0.2.0", "title": "x", "extra": true}]}
        """))

    #expect(result == .success("0.2.0"))
  }

  @Test func returnsNilForAnEmptyReleasesList() {
    let result = ReleaseIndex.latestVersion(from: data(#"{"schemaVersion": 1, "releases": []}"#))

    #expect(result == .success(nil))
  }

  @Test func failsOnInvalidJSON() {
    #expect(isFailure(ReleaseIndex.latestVersion(from: data("not json"))))
  }

  @Test func failsWhenTheTopLevelIsNotAnObject() {
    #expect(isFailure(ReleaseIndex.latestVersion(from: data("[1, 2, 3]"))))
  }

  @Test func failsWhenSchemaVersionIsMissing() {
    #expect(isFailure(ReleaseIndex.latestVersion(from: data(#"{"releases": []}"#))))
  }

  @Test func failsWhenSchemaVersionIsUnknown() {
    #expect(
      isFailure(ReleaseIndex.latestVersion(from: data(#"{"schemaVersion": 2, "releases": []}"#))))
  }

  @Test func failsWhenSchemaVersionIsNotAnInteger() {
    #expect(
      isFailure(
        ReleaseIndex.latestVersion(from: data(#"{"schemaVersion": "1", "releases": []}"#))))
  }

  @Test func failsWhenReleasesIsMissing() {
    #expect(isFailure(ReleaseIndex.latestVersion(from: data(#"{"schemaVersion": 1}"#))))
  }

  @Test func failsWhenReleasesIsNotAnArray() {
    #expect(
      isFailure(
        ReleaseIndex.latestVersion(from: data(#"{"schemaVersion": 1, "releases": "none"}"#))))
  }

  @Test func failsWhenTheFirstReleaseIsNotAnObject() {
    #expect(
      isFailure(
        ReleaseIndex.latestVersion(from: data(#"{"schemaVersion": 1, "releases": ["0.2.0"]}"#))))
  }

  @Test func failsWhenTheFirstReleaseHasNoVersion() {
    #expect(
      isFailure(
        ReleaseIndex.latestVersion(
          from: data(#"{"schemaVersion": 1, "releases": [{"title": "x"}]}"#))))
  }
}
