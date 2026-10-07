public struct UpdateCheckRequests: Sendable, Equatable {
  public private(set) var isInFlight = false
  private var manualRequestedWhileInFlight = false

  public init() {}

  public mutating func begin(manual: Bool) -> Bool {
    if isInFlight {
      if manual { manualRequestedWhileInFlight = true }
      return false
    }
    isInFlight = true
    return true
  }

  public mutating func finish(manual: Bool) -> Bool {
    let answers = manual || manualRequestedWhileInFlight
    isInFlight = false
    manualRequestedWhileInFlight = false
    return answers
  }
}
