import Testing

@testable import ApprovalCore

@Suite struct ActivityGateTests {
  @Test func isIdleAtTheBoundary() {
    let gate = ActivityGate(idleSeconds: 5)
    #expect(gate.isIdle(secondsSinceLastInput: 5, modifiersHeld: false))
  }

  @Test func isIdleAboveTheBoundary() {
    let gate = ActivityGate(idleSeconds: 5)
    #expect(gate.isIdle(secondsSinceLastInput: 5.01, modifiersHeld: false))
  }

  @Test func isNotIdleBelowTheBoundary() {
    let gate = ActivityGate(idleSeconds: 5)
    #expect(!gate.isIdle(secondsSinceLastInput: 4.99, modifiersHeld: false))
  }

  @Test func heldModifiersAreNotIdleAtTheBoundary() {
    let gate = ActivityGate(idleSeconds: 5)
    #expect(!gate.isIdle(secondsSinceLastInput: 5, modifiersHeld: true))
  }

  @Test func heldModifiersAreNotIdleLongPastTheBoundary() {
    let gate = ActivityGate(idleSeconds: 5)
    #expect(!gate.isIdle(secondsSinceLastInput: 3600, modifiersHeld: true))
  }

  @Test func heldModifiersAreNotIdleWithNoInputEver() {
    let gate = ActivityGate(idleSeconds: 5)
    #expect(!gate.isIdle(secondsSinceLastInput: .infinity, modifiersHeld: true))
  }

  @Test func heldModifiersAreNotIdleBelowTheBoundary() {
    let gate = ActivityGate(idleSeconds: 5)
    #expect(!gate.isIdle(secondsSinceLastInput: 1, modifiersHeld: true))
  }
}
