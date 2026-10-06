import Foundation
import Testing

@testable import ApprovalCore

@Suite struct NoticeVisibleTimeTests {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @Test func theFirstCallOnlyStoresTheTime() {
    var time = NoticeVisibleTime()
    time.advance(to: start, counting: true)
    #expect(time.seconds == 0)
  }

  @Test func countingAddsTheGap() {
    var time = NoticeVisibleTime()
    time.advance(to: start, counting: true)
    time.advance(to: start.addingTimeInterval(1), counting: true)
    time.advance(to: start.addingTimeInterval(3), counting: true)
    #expect(time.seconds == 3)
  }

  @Test func notCountingAddsNothingButMovesTheMark() {
    var time = NoticeVisibleTime()
    time.advance(to: start, counting: true)
    time.advance(to: start.addingTimeInterval(4), counting: false)
    time.advance(to: start.addingTimeInterval(5), counting: true)
    #expect(time.seconds == 1)
  }

  @Test func aLongGapAddsAtMostFiveSeconds() {
    var time = NoticeVisibleTime()
    time.advance(to: start, counting: true)
    time.advance(to: start.addingTimeInterval(60), counting: true)
    #expect(time.seconds == 5)
  }

  @Test func aNegativeGapAddsNothing() {
    var time = NoticeVisibleTime()
    time.advance(to: start, counting: true)
    time.advance(to: start.addingTimeInterval(-30), counting: true)
    #expect(time.seconds == 0)
  }
}
