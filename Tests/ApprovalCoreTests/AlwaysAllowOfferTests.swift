import Foundation
import Testing

@testable import ApprovalCore

@Suite struct AlwaysAllowOfferTests {
  private let home = URL(fileURLWithPath: "/Users/tester")
  private let cwd = "/Users/tester/code/shop"

  private func request(
    _ fixture: String, host: ApprovalCore.Host, cwd: String? = nil, command: String? = nil
  ) throws -> ApprovalRequest {
    var request = try host.parse(FixtureLoader.data(fixture))
    request.cwd = cwd ?? self.cwd
    if let command {
      request.kind = .permission(
        PermissionPrompt(body: .bash(command: command, description: nil), suggestions: []))
    }
    return request
  }

  private func cursorShell(_ command: String) throws -> ApprovalRequest {
    try request("cursor-shell", host: .cursor, command: command)
  }

  @Test func offersTheExactCommandForCursor() throws {
    let request = try request("cursor-shell", host: .cursor)
    let offer = try #require(AlwaysAllowOffer.offer(for: request, home: home))
    #expect(
      offer.rules == [
        ApprovalRule(
          decision: .allow, agent: .cursor, project: "~/code/shop",
          command: "npm install stripe@14 --save")
      ])
    #expect(offer.title == "Always allow \"npm install stripe@14 --save\"")
    #expect(offer.detail == "Cursor in shop")
  }

  @Test func aCompoundCommandGetsOneRulePerDistinctSegmentInOrder() throws {
    let offer = try #require(
      AlwaysAllowOffer.offer(
        for: try cursorShell("pnpm lint && pnpm test; pnpm lint | cat"), home: home))
    #expect(offer.rules.compactMap(\.command) == ["pnpm lint", "pnpm test", "cat"])
    #expect(offer.rules.allSatisfy { $0.decision == .allow && $0.agent == .cursor })
    #expect(offer.rules.allSatisfy { $0.project == "~/code/shop" && $0.tool == nil })
    #expect(offer.title == "Always allow these 3 commands")
    #expect(offer.detail == "Cursor in shop: pnpm lint, pnpm test, cat")
  }

  @Test func anUnsplittableCommandHasNoOffer() throws {
    #expect(AlwaysAllowOffer.offer(for: try cursorShell("echo 'unterminated"), home: home) == nil)
    #expect(AlwaysAllowOffer.offer(for: try cursorShell("   "), home: home) == nil)
  }

  @Test func aSegmentThatCannotBeExactHasNoOffer() throws {
    #expect(AlwaysAllowOffer.offer(for: try cursorShell("ls *:x"), home: home) == nil)
    #expect(
      AlwaysAllowOffer.offer(for: try cursorShell("pnpm lint && ls *:x"), home: home) == nil)
  }

  @Test func aColonSegmentIsSavedAsBaseAndExactArguments() throws {
    let offer = try #require(
      AlwaysAllowOffer.offer(for: try cursorShell("git push origin main:main"), home: home))
    #expect(offer.rules.compactMap(\.command) == ["git:push origin main:main"])
    #expect(offer.title == "Always allow \"git:push origin main:main\"")
  }

  @Test func claudeGetsNoOffer() throws {
    let request = try request("claude-bash", host: .claude)
    #expect(AlwaysAllowOffer.offer(for: request, home: home) == nil)
  }

  @Test func anEmptyCwdHasNoOffer() throws {
    var request = try request("cursor-shell", host: .cursor)
    request.cwd = ""
    #expect(AlwaysAllowOffer.offer(for: request, home: home) == nil)
  }

  @Test func aRequestThatIsNotAPermissionHasNoOffer() throws {
    var request = try request("cursor-shell", host: .cursor)
    request.kind = .questions([])
    #expect(AlwaysAllowOffer.offer(for: request, home: home) == nil)
  }

  @Test func aPatchBecomesAToolRule() throws {
    let request = try request("codex-apply-patch", host: .codex)
    let offer = try #require(AlwaysAllowOffer.offer(for: request, home: home))
    #expect(
      offer.rules == [
        ApprovalRule(
          decision: .allow, agent: .codex, project: "~/code/shop", tool: request.toolName)
      ])
    #expect(offer.title == "Always allow apply_patch")
    #expect(offer.detail == "Codex in shop")
  }

  @Test func anMcpCallBecomesAToolRuleWithTheMcpToolName() throws {
    let request = try request("cursor-mcp-url", host: .cursor)
    let offer = try #require(AlwaysAllowOffer.offer(for: request, home: home))
    #expect(offer.rules.map(\.tool) == [request.toolName])
    #expect(offer.rules.allSatisfy { $0.command == nil && $0.agent == .cursor })
    #expect(offer.title == "Always allow \(request.toolName)")
  }

  @Test func aProjectOutsideHomeKeepsItsAbsolutePath() throws {
    let request = try request("cursor-shell", host: .cursor, cwd: "/srv/app")
    let offer = try #require(AlwaysAllowOffer.offer(for: request, home: home))
    #expect(offer.rules.first?.project == "/srv/app")
  }
}
