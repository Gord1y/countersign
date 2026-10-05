import Foundation

public struct ApprovalRule: Sendable, Equatable {
  public enum Decision: String, Sendable, Equatable, CaseIterable {
    case allow
    case deny
  }

  public static let defaultDenyMessage = "Denied by a Countersign rule."

  public var decision: Decision
  public var agent: Host?
  public var project: String?
  public var tool: String?
  public var command: String?
  public var message: String?

  public init(
    decision: Decision,
    agent: Host? = nil,
    project: String? = nil,
    tool: String? = nil,
    command: String? = nil,
    message: String? = nil
  ) {
    self.decision = decision
    self.agent = agent
    self.project = project
    self.tool = tool
    self.command = command
    self.message = message
  }
}
