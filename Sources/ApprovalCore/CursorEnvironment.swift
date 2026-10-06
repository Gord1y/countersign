import Foundation

public struct CursorEnvironment: Sendable, Equatable {
  public let runMode: CursorRunMode
  public let commandAllowlist: CursorCommandAllowlist?

  public init(runMode: CursorRunMode, commandAllowlist: CursorCommandAllowlist?) {
    self.runMode = runMode
    self.commandAllowlist = commandAllowlist
  }

  public static func parse(applicationUser: Data?, permissionsFiles: [[String]?])
    -> CursorEnvironment
  {
    var runMode = CursorRunMode.unknown
    var inApp: [String]?
    if let applicationUser,
      let value = try? JSONDecoder().decode(JSONValue.self, from: applicationUser)
    {
      runMode = CursorRunMode.resolve(applicationUser: value)
      inApp = value["composerState"]?["yoloCommandAllowlist"]?.stringArray
    }
    return CursorEnvironment(
      runMode: runMode,
      commandAllowlist: CursorCommandAllowlist.resolve(
        inApp: inApp, permissionsFiles: permissionsFiles))
  }

  public static func read(home: URL, workspaceRoot: String) -> CursorEnvironment {
    let applicationUser = CursorStateDatabase.value(
      forKey: CursorStateDatabase.applicationUserKey,
      at: CursorStateDatabase.location(home: home))
    var permissionsFiles = [
      CursorPermissionsFile.terminalAllowlist(at: CursorPermissionsFile.userFile(home: home))
    ]
    if !workspaceRoot.isEmpty {
      permissionsFiles.append(
        CursorPermissionsFile.terminalAllowlist(
          at: CursorPermissionsFile.workspaceFile(root: URL(fileURLWithPath: workspaceRoot))))
    }
    return parse(applicationUser: applicationUser, permissionsFiles: permissionsFiles)
  }

  public func allowsWithoutAsking(_ request: ApprovalRequest) -> Bool {
    guard request.host == .cursor,
      case .permission(let prompt) = request.kind,
      case .bash(let command, _) = prompt.body,
      runMode == .allowlist || runMode == .autoReview || runMode == .runEverything,
      let commandAllowlist
    else { return false }
    return CommandPattern.allMatch(
      command, patterns: commandAllowlist.patterns.map(CommandPattern.init))
  }

  public var logLine: String {
    guard let commandAllowlist else {
      return "cursor: run mode \(runMode.rawValue), allowlist unreadable"
    }
    let origin = commandAllowlist.source == .inApp ? "the app" : "permissions.json"
    return
      "cursor: run mode \(runMode.rawValue), allowlist \(commandAllowlist.patterns.count) from \(origin)"
  }
}

extension JSONValue {
  fileprivate var stringArray: [String]? {
    guard let elements = arrayValue else { return nil }
    var strings: [String] = []
    for element in elements {
      guard let string = element.stringValue else { return nil }
      strings.append(string)
    }
    return strings
  }
}
