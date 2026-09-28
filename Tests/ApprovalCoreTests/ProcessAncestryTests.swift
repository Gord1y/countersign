import Darwin
import Testing

@testable import ApprovalCore

@Suite struct ProcessAncestryTests {
  @Test func realChainStartsAtGetppidAndEndsAtLaunchdOrStopsCleanly() {
    let chain = ProcessAncestry.chain(from: getppid())
    #expect(chain.first == getppid())
    #expect(!chain.isEmpty)
    #expect(chain.count <= ProcessAncestry.defaultMaxSteps)
    #expect(Set(chain).count == chain.count)
  }

  @Test func launchdIsItsOwnEndOfChain() {
    let chain = ProcessAncestry.chain(from: 1, parentOf: { _ in 0 })
    #expect(chain == [1])
  }

  @Test func stopsCleanlyWhenParentLookupFails() {
    let chain = ProcessAncestry.chain(from: 500, parentOf: { pid in pid == 500 ? nil : 1 })
    #expect(chain == [500])
  }

  @Test func walksUpwardThroughSeveralAncestors() {
    let parents: [Int32: Int32] = [10: 9, 9: 5, 5: 1]
    let chain = ProcessAncestry.chain(from: 10, parentOf: { parents[$0] })
    #expect(chain == [10, 9, 5, 1])
  }

  @Test func stopsOnACycleInsteadOfLoopingForever() {
    let parents: [Int32: Int32] = [10: 20, 20: 10]
    let chain = ProcessAncestry.chain(from: 10, parentOf: { parents[$0] })
    #expect(chain == [10, 20])
  }

  @Test func stopsAtMaxStepsWhenTheChainNeverReachesLaunchd() {
    let chain = ProcessAncestry.chain(from: 2, maxSteps: 5, parentOf: { $0 + 1 })
    #expect(chain == [2, 3, 4, 5, 6])
  }

  @Test func nonPositivePIDProducesAnEmptyChain() {
    let chain = ProcessAncestry.chain(from: 0, parentOf: { _ in 1 })
    #expect(chain.isEmpty)
  }
}
