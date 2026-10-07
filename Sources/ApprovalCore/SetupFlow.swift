import Foundation

public struct SetupAgents: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case noAgents
    case needsWiring
    case allSet
  }

  public let wired: [Host]
  public let toWire: [Host]
  public let unusable: [Host]
  public let notInstalled: [Host]

  public init(statuses: [Host: HostWiringStatus]) {
    var wired: [Host] = []
    var toWire: [Host] = []
    var unusable: [Host] = []
    var notInstalled: [Host] = []
    for host in Host.allCases {
      guard let status = statuses[host] else { continue }
      switch status {
      case .wired: wired.append(host)
      case .notWired, .needsUpdate: toWire.append(host)
      case .unusable: unusable.append(host)
      case .notInstalled: notInstalled.append(host)
      }
    }
    self.wired = wired
    self.toWire = toWire
    self.unusable = unusable
    self.notInstalled = notInstalled
  }

  public var phase: Phase {
    if !toWire.isEmpty { return .needsWiring }
    if wired.isEmpty && unusable.isEmpty { return .noAgents }
    return .allSet
  }
}

public enum SetupLaunch {
  public static func opensSetup(setupShown: Bool, tourShown: Bool) -> Bool {
    !setupShown && !tourShown
  }
}
