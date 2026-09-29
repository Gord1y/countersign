public struct SettingsVisit: Sendable, Equatable {
  public private(set) var changed: Set<PreferenceName> = []

  public init() {}

  public func contains(_ name: PreferenceName) -> Bool {
    changed.contains(name)
  }

  public mutating func record(_ names: [PreferenceName]) {
    changed.formUnion(names)
  }

  public mutating func forget(_ names: [PreferenceName]) {
    changed.subtract(names)
  }

  public mutating func begin() {
    changed.removeAll()
  }
}
