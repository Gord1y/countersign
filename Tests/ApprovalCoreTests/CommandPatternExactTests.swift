import Testing

@testable import ApprovalCore

@Suite struct CommandPatternExactTests {
  @Test func aPlainSegmentIsItsOwnPattern() {
    #expect(CommandPattern.exact(forSegment: "npm install stripe")?.text == "npm install stripe")
  }

  @Test func plainPatternAlsoCoversMoreArguments() throws {
    let pattern = try #require(CommandPattern.exact(forSegment: "npm install"))
    #expect(pattern.matches("npm install"))
    #expect(pattern.matches("npm install stripe"))
    #expect(!pattern.matches("npm installer"))
  }

  @Test func surroundingSpacesAreTrimmed() {
    #expect(CommandPattern.exact(forSegment: "  \tls -la \t")?.text == "ls -la")
  }

  @Test func aSegmentWithAColonBecomesBaseAndExactArguments() throws {
    let pattern = try #require(CommandPattern.exact(forSegment: "git push origin main:main"))
    #expect(pattern.text == "git:push origin main:main")
    #expect(pattern.matches("git push origin main:main"))
    #expect(!pattern.matches("git push origin main:mainx"))
    #expect(!pattern.matches("git push origin other:main"))
  }

  @Test func extraSpacesBetweenWordsDoNotChangeTheBase() {
    #expect(
      CommandPattern.exact(forSegment: "git   push a:b")?.text == "git:push a:b")
  }

  @Test func aColonWithAStarHasNoExactPattern() {
    #expect(CommandPattern.exact(forSegment: "git push origin *:main") == nil)
  }

  @Test func aColonInTheFirstWordHasNoExactPattern() {
    #expect(CommandPattern.exact(forSegment: "host:run now") == nil)
    #expect(CommandPattern.exact(forSegment: "a:b") == nil)
  }

  @Test func anEmptySegmentHasNoPattern() {
    #expect(CommandPattern.exact(forSegment: "") == nil)
    #expect(CommandPattern.exact(forSegment: "  \t ") == nil)
  }

  @Test func aStarWithoutAColonStaysLiteral() throws {
    let pattern = try #require(CommandPattern.exact(forSegment: "ls *.txt"))
    #expect(pattern.text == "ls *.txt")
    #expect(pattern.matches("ls *.txt"))
    #expect(!pattern.matches("ls a.txt"))
  }
}
