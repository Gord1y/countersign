import Foundation
import Testing

@testable import ApprovalCore

@Suite struct TranscriptGrowthTests {
  private func rows(_ types: [String]) -> String {
    types.map { "{\"type\":\"\($0)\"}\n" }.joined()
  }

  @Test func claudeMetadataRowsAreNotAResume() {
    let metadata = rows(["last-prompt", "ai-title", "atis-latch", "cost-state", "mode"])
    #expect(!TranscriptGrowth.resumed(host: .claude, appended: Data(metadata.utf8)))
    #expect(!TranscriptGrowth.resumed(host: .claude, appended: Data("tail of a row}\n".utf8)))
  }

  @Test func claudeUserRowIsAResume() {
    let appended = rows(["cost-state", "queue-operation"])
    #expect(TranscriptGrowth.resumed(host: .claude, appended: Data(appended.utf8)))
    #expect(TranscriptGrowth.resumed(host: .claude, appended: Data(rows(["user"]).utf8)))
  }

  @Test func claudePartialLastLineIsNotAResume() {
    let partial = rows(["mode"]) + "{\"type\":\"user\"}"
    #expect(!TranscriptGrowth.resumed(host: .claude, appended: Data(partial.utf8)))
    #expect(!TranscriptGrowth.resumed(host: .claude, appended: Data("{\"type\":\"user\"}".utf8)))
  }

  @Test func otherHostsResumeOnAnyGrowth() {
    for host in [Host.codex, .cursor, .antigravity] {
      #expect(TranscriptGrowth.resumed(host: host, appended: Data("x".utf8)))
      #expect(!TranscriptGrowth.resumed(host: host, appended: Data()))
    }
  }
}
