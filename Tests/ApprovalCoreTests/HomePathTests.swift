import Foundation
import Testing

@testable import ApprovalCore

@Suite struct HomePathTests {
  @Test func replacesTheHomePrefixWithATilde() {
    let home = URL(fileURLWithPath: "/a/home/x")
    #expect(HomePath.abbreviating("/a/home/x/y", relativeTo: home) == "~/y")
    #expect(HomePath.abbreviating("/a/home/x/y/z", relativeTo: home) == "~/y/z")
  }

  @Test func collapsesTheHomeItselfToATilde() {
    let home = URL(fileURLWithPath: "/a/home/x")
    #expect(HomePath.abbreviating("/a/home/x", relativeTo: home) == "~")
  }

  @Test func leavesPathsOutsideHomeUnchanged() {
    let home = URL(fileURLWithPath: "/a/home/x")
    #expect(HomePath.abbreviating("/a/other/y", relativeTo: home) == "/a/other/y")
  }

  @Test func doesNotMatchASiblingThatSharesTheHomeAsAPrefix() {
    let home = URL(fileURLWithPath: "/a/home")
    #expect(HomePath.abbreviating("/a/homework/y", relativeTo: home) == "/a/homework/y")
  }

  @Test func ignoresATrailingSlashOnHome() {
    let home = URL(fileURLWithPath: "/a/home/x/")
    #expect(HomePath.abbreviating("/a/home/x/y", relativeTo: home) == "~/y")
  }

  @Test func leavesRelativePathsUnchangedWhenHomeIsRoot() {
    let home = URL(fileURLWithPath: "/")
    #expect(HomePath.abbreviating("/a/home/x/y", relativeTo: home) == "/a/home/x/y")
  }
}
