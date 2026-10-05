import Testing

@testable import ApprovalCore

@Suite struct SettingsVisitTests {
  @Test func startsEmpty() {
    let visit = SettingsVisit()
    #expect(!visit.contains(.armDelay))
    #expect(visit.changed.isEmpty)
  }

  @Test func recordsEveryNameGiven() {
    var visit = SettingsVisit()
    visit.record([.armDelay, .idleSeconds])
    #expect(visit.contains(.armDelay))
    #expect(visit.contains(.idleSeconds))
    #expect(!visit.contains(.graceSeconds))
  }

  @Test func recordingTwiceKeepsOneEntry() {
    var visit = SettingsVisit()
    visit.record([.armDelay])
    visit.record([.armDelay])
    #expect(visit.changed == [.armDelay])
  }

  @Test func forgetsOnlyTheNamesGiven() {
    var visit = SettingsVisit()
    visit.record([.armDelay, .idleSeconds])
    visit.forget([.armDelay, .graceSeconds])
    #expect(!visit.contains(.armDelay))
    #expect(visit.contains(.idleSeconds))
  }

  @Test func beginEmptiesTheVisit() {
    var visit = SettingsVisit()
    visit.record([.armDelay, .idleSeconds])
    visit.begin()
    #expect(visit.changed.isEmpty)
  }
}
