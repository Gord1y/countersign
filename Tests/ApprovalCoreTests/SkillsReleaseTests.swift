import Foundation
import Testing

@testable import ApprovalCore

@Suite struct SkillsReleaseTests {
  private let abcDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  private let shapeReason = "the checksum file is not one line of a SHA-256 and a file name"
  private let mismatchReason = "the archive's SHA-256 does not match its checksum file"

  private func release(_ version: String = "1.0.0") throws -> SkillsRelease {
    try #require(SkillsRelease(version: version))
  }

  private var abcLine: String {
    "\(abcDigest)  countersign-skills-1.0.0.tar.gz\n"
  }

  private func failureReason(_ result: Result<some Any, SkillsReleaseError>) -> String? {
    guard case .failure(let error) = result else { return nil }
    return error.reason
  }

  @Test func fixtureGivesTheRealDigest() throws {
    let file = try FixtureLoader.data("skills-release-checksum", withExtension: "sha256")
    let result = try release().expectedDigest(fromChecksumFile: file)
    #expect(
      result == .success("00bfd60ee950573d27d58ef1373aac7b96f93a3200b1e87caa4eecc81b32dd6b"))
  }

  @Test func namesAndURLs() throws {
    let release = try release()
    let base = "https://github.com/Gord1y/countersign-skills/releases/download/v1.0.0/"
    #expect(release.tag == "v1.0.0")
    #expect(release.archiveName == "countersign-skills-1.0.0.tar.gz")
    #expect(release.checksumName == "countersign-skills-1.0.0.tar.gz.sha256")
    #expect(
      release.assetURL(named: release.archiveName)?.absoluteString
        == base + "countersign-skills-1.0.0.tar.gz")
    #expect(
      release.assetURL(named: release.checksumName)?.absoluteString
        == base + "countersign-skills-1.0.0.tar.gz.sha256")
    #expect(release.assetURL(named: "catalog.json")?.absoluteString == base + "catalog.json")
  }

  @Test func versionShape() {
    #expect(SkillsRelease(version: "1.0.0")?.version == "1.0.0")
    #expect(SkillsRelease(version: "10.20.30")?.version == "10.20.30")
    for rejected in ["v1.0.0", "1.0", "1.0.0-beta", ""] {
      #expect(SkillsRelease(version: rejected) == nil)
    }
  }

  @Test func unsafeAssetNamesHaveNoURL() throws {
    let release = try release()
    for rejected in ["../x", "a b", "", ".."] {
      #expect(release.assetURL(named: rejected) == nil)
    }
  }

  @Test func matchingArchiveVerifies() throws {
    let result = try release().verify(archive: Data("abc".utf8), checksumFile: Data(abcLine.utf8))
    #expect(failureReason(result) == nil)
    guard case .success = result else {
      Issue.record("verify did not succeed")
      return
    }
  }

  @Test func differentArchiveIsRejected() throws {
    let result = try release().verify(archive: Data("abd".utf8), checksumFile: Data(abcLine.utf8))
    #expect(failureReason(result) == mismatchReason)
  }

  @Test func checksumForAnotherArchiveIsRejected() throws {
    let file = "\(abcDigest)  countersign-skills-1.0.1.tar.gz\n"
    let result = try release().expectedDigest(fromChecksumFile: Data(file.utf8))
    #expect(
      failureReason(result)
        == "the checksum is for countersign-skills-1.0.1.tar.gz, not countersign-skills-1.0.0.tar.gz"
    )
  }

  @Test func malformedChecksumFilesAreRejected() throws {
    let release = try release()
    let name = "countersign-skills-1.0.0.tar.gz"
    let line = "\(abcDigest)  \(name)\n"
    let malformed: [Data] = [
      Data(),
      Data("\(abcDigest) \(name)\n".utf8),
      Data("\(abcDigest.dropLast())  \(name)\n".utf8),
      Data("\(abcDigest.uppercased())  \(name)\n".utf8),
      Data((line + line).utf8),
      Data((line + "extra").utf8),
    ]
    for file in malformed {
      #expect(failureReason(release.expectedDigest(fromChecksumFile: file)) == shapeReason)
    }
  }

  @Test func missingTrailingNewlineIsAccepted() throws {
    let file = "\(abcDigest)  countersign-skills-1.0.0.tar.gz"
    let result = try release().expectedDigest(fromChecksumFile: Data(file.utf8))
    #expect(result == .success(abcDigest))
  }

  @Test func sha256OfAbc() {
    #expect(SkillsRelease.sha256Hex(of: Data("abc".utf8)) == abcDigest)
  }
}
