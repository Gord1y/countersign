import Foundation
import Testing

@testable import ApprovalCore

@Suite struct BugReportURLTests {
  @Test func buildsTheBugTemplateURLWithEveryFieldFilled() throws {
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0",
        doctorText: "ok version: countersign 0.1.0", homeDirectory: ""))

    let string = url.absoluteString
    #expect(string.hasPrefix("https://github.com/Gord1y/countersign/issues/new?template=bug.yml"))
    #expect(string.contains("macos-version=macOS%2015.1"))
    #expect(string.contains("countersign-version=0.1.0"))
    #expect(string.contains("doctor=ok%20version%3A%20countersign%200.1.0"))
  }

  @Test func percentEncodesReservedAndUnicodeCharacters() throws {
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1 (24B83)", countersignVersion: "0.1.0",
        doctorText: "fail claude: /Users/gord1y/Library — “quoted” & broken\nline two",
        homeDirectory: ""))

    let string = url.absoluteString
    #expect(string.contains("macos-version=macOS%2015.1%20%2824B83%29"))
    #expect(
      string.contains(
        "doctor=fail%20claude%3A%20%2FUsers%2Fgord1y%2FLibrary%20%E2%80%94%20%E2%80%9Cquoted%E2%80%9D%20%26%20broken%0Aline%20two"
      ))
    #expect(!string.contains(" "))
    #expect(!string.contains("&&"))
  }

  @Test func stripsQueryUnsafeCharactersFromEveryField() {
    let url = BugReportURL.build(
      macOSVersion: "macOS 15&1", countersignVersion: "0.1.0=beta", doctorText: "a=b&c=d",
      homeDirectory: "")

    #expect(url != nil)
    let queryPairs =
      url?.absoluteString
      .split(separator: "?").last?
      .split(separator: "&")
      .map(String.init) ?? []
    #expect(queryPairs.count == 4)
  }

  @Test func fitsUnderTheCapByDroppingTrailingLinesAndMarkingTheCut() throws {
    let manyLines = (1...500).map {
      "ok claude: entry \($0) at /Users/gord1y/some/very/long/path"
    }
    let doctorText = manyLines.joined(separator: "\n")
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0", doctorText: doctorText,
        homeDirectory: ""))

    #expect(url.absoluteString.count <= BugReportURL.maxLength)
    let decodedDoctor = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "doctor" })?.value)
    #expect(decodedDoctor.hasSuffix("…"))
    #expect(!decodedDoctor.contains("entry 500"))
  }

  @Test func aShortDoctorNeedsNoCutting() throws {
    let doctorText = "ok version: countersign 0.1.0"
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0", doctorText: doctorText,
        homeDirectory: ""))

    let decodedDoctor = try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "doctor" })?.value)
    #expect(decodedDoctor == doctorText)
    #expect(!decodedDoctor.contains("…"))
  }

  @Test func anEmptyDoctorLeavesTheParamEmpty() throws {
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0", doctorText: "",
        homeDirectory: ""))

    #expect(url.absoluteString.hasSuffix("&doctor="))
    #expect(url.absoluteString.count <= BugReportURL.maxLength)
  }

  @Test func dropsEveryDoctorLineWhenTheOtherFieldsAlreadyFillTheBudget() throws {
    let hugeVersion = String(repeating: "x", count: BugReportURL.maxLength * 2)
    let url = try #require(
      BugReportURL.build(
        macOSVersion: hugeVersion, countersignVersion: "0.1.0", doctorText: "ok version: 0.1.0",
        homeDirectory: ""))

    #expect(url.absoluteString.hasSuffix("&doctor="))
  }

  private func decodedDoctor(_ url: URL) throws -> String {
    try #require(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "doctor" })?.value)
  }

  @Test func aPathUnderHomeBecomesATilde() throws {
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0",
        doctorText: "ok claude: /Users/gord1y/.local/bin/countersign, timeout 600s",
        homeDirectory: "/Users/gord1y"))

    #expect(try decodedDoctor(url) == "ok claude: ~/.local/bin/countersign, timeout 600s")
  }

  @Test func aPathOutsideHomeIsUnchanged() throws {
    let text = "ok claude: /Applications/Countersign.app/Contents/MacOS/countersign"
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0", doctorText: text,
        homeDirectory: "/Users/gord1y"))

    #expect(try decodedDoctor(url) == text)
  }

  @Test func aPartialHomePrefixMatchIsUnchanged() throws {
    let text = "ok claude: /Users/alexander/.local/bin/countersign"
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0", doctorText: text,
        homeDirectory: "/Users/alex"))

    #expect(try decodedDoctor(url) == text)
  }

  @Test func everyOccurrenceOfHomeIsMaskedIncludingAtTheEdgesOfTheText() throws {
    let text = "/Users/gord1y is the home used by /Users/gord1y/Library and /Users/gord1y"
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0", doctorText: text,
        homeDirectory: "/Users/gord1y"))

    #expect(try decodedDoctor(url) == "~ is the home used by ~/Library and ~")
  }

  @Test func anEmptyHomeDirectoryMasksNothing() throws {
    let text = "ok claude: /Users/gord1y/.local/bin/countersign"
    let url = try #require(
      BugReportURL.build(
        macOSVersion: "macOS 15.1", countersignVersion: "0.1.0", doctorText: text,
        homeDirectory: ""))

    #expect(try decodedDoctor(url) == text)
  }
}
