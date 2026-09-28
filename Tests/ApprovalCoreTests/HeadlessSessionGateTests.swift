import Foundation
import Testing

@testable import ApprovalCore

private func makeEntry(fields: [String: JSONValue]) -> SessionRegistry.Entry {
  SessionRegistry.Entry(url: URL(fileURLWithPath: "/tmp/100.json"), fields: fields)
}

@Suite struct HeadlessSessionGateTests {
  @Test func interactiveKindProceedsWithFlagOff() {
    let entry = makeEntry(fields: ["kind": .string("interactive")])
    #expect(
      HeadlessSessionGate.decide(registryEntry: entry, includeHeadlessSessions: false) == .proceed)
  }

  @Test func interactiveKindProceedsWithFlagOn() {
    let entry = makeEntry(fields: ["kind": .string("interactive")])
    #expect(
      HeadlessSessionGate.decide(registryEntry: entry, includeHeadlessSessions: true) == .proceed)
  }

  @Test func otherKindSkipsWithFlagOff() {
    let entry = makeEntry(fields: ["kind": .string("headless")])
    #expect(
      HeadlessSessionGate.decide(registryEntry: entry, includeHeadlessSessions: false)
        == .skip(kind: "headless"))
  }

  @Test func otherKindProceedsWithFlagOn() {
    let entry = makeEntry(fields: ["kind": .string("headless")])
    #expect(
      HeadlessSessionGate.decide(registryEntry: entry, includeHeadlessSessions: true) == .proceed)
  }

  @Test func missingKindProceeds() {
    let entry = makeEntry(fields: [:])
    #expect(
      HeadlessSessionGate.decide(registryEntry: entry, includeHeadlessSessions: false) == .proceed)
  }

  @Test func nonStringKindProceeds() {
    let entry = makeEntry(fields: ["kind": .int(5)])
    #expect(
      HeadlessSessionGate.decide(registryEntry: entry, includeHeadlessSessions: false) == .proceed)
  }

  @Test func noEntryProceedsWithFlagOff() {
    #expect(
      HeadlessSessionGate.decide(registryEntry: nil, includeHeadlessSessions: false) == .proceed)
  }

  @Test func noEntryProceedsWithFlagOn() {
    #expect(
      HeadlessSessionGate.decide(registryEntry: nil, includeHeadlessSessions: true) == .proceed)
  }
}
