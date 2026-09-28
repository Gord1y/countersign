public struct ActivityGate: Sendable, Equatable {
  public let idleSeconds: Double

  public init(idleSeconds: Double) {
    self.idleSeconds = idleSeconds
  }

  public func isIdle(secondsSinceLastInput: Double, modifiersHeld: Bool) -> Bool {
    !modifiersHeld && secondsSinceLastInput >= idleSeconds
  }
}
