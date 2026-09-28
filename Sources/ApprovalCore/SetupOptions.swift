import Foundation

public enum SetupMode: Sendable, Equatable {
  case window
  case terminal(SetupOptions)
}

public struct SetupOptions: Sendable, Equatable {
  public var assumeYes: Bool
  public var uninstall: Bool
  public var host: Host?
  public var terminalFlow: Bool

  public init(assumeYes: Bool, uninstall: Bool, host: Host?, terminalFlow: Bool) {
    self.assumeYes = assumeYes
    self.uninstall = uninstall
    self.host = host
    self.terminalFlow = terminalFlow
  }

  public var hosts: [Host] {
    host.map { [$0] } ?? Host.allCases
  }

  public static func mode(for arguments: [String]) -> SetupMode? {
    guard let options = parse(arguments) else { return nil }
    if options.terminalFlow {
      return .terminal(options)
    }
    guard !options.assumeYes, !options.uninstall, options.host == nil else { return nil }
    return .window
  }

  public static func parse(_ arguments: [String]) -> SetupOptions? {
    var options = SetupOptions(assumeYes: false, uninstall: false, host: nil, terminalFlow: false)
    var index = arguments.startIndex
    while index < arguments.count {
      switch arguments[index] {
      case "--yes":
        guard !options.assumeYes else { return nil }
        options.assumeYes = true
      case "--uninstall":
        guard !options.uninstall else { return nil }
        options.uninstall = true
      case "--cli":
        guard !options.terminalFlow else { return nil }
        options.terminalFlow = true
      case "--host":
        guard options.host == nil else { return nil }
        index += 1
        guard index < arguments.count, let host = Host(rawValue: arguments[index]) else {
          return nil
        }
        options.host = host
      default:
        return nil
      }
      index += 1
    }
    return options
  }
}
