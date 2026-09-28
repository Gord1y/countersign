import Foundation

public enum TestPanelKind: String, CaseIterable, Sendable {
  case command
  case question
  case plan

  public static func parse(_ arguments: [String]) -> TestPanelKind? {
    switch arguments.count {
    case 0: return .command
    case 1: return TestPanelKind(rawValue: arguments[0])
    default: return nil
    }
  }

  public var title: String {
    switch self {
    case .command: return "Command"
    case .question: return "Question"
    case .plan: return "Plan"
    }
  }
}

public enum TestPanelSample {
  public static let workingDirectory = "/Countersign test"
  public static let sessionID = "00000000-0000-4000-8000-000000000000"

  public static func payload(for kind: TestPanelKind) -> JSONValue {
    var root: [String: JSONValue] = [
      "session_id": .string(sessionID),
      "cwd": .string(workingDirectory),
      "hook_event_name": .string("PermissionRequest"),
    ]
    switch kind {
    case .command:
      root["permission_mode"] = .string("default")
      root["tool_name"] = .string("Bash")
      root["tool_input"] = commandInput
      root["permission_suggestions"] = commandSuggestions
    case .question:
      root["permission_mode"] = .string("default")
      root["tool_name"] = .string("AskUserQuestion")
      root["tool_input"] = questionInput
    case .plan:
      root["permission_mode"] = .string("plan")
      root["tool_name"] = .string("ExitPlanMode")
      root["tool_input"] = planInput
    }
    return .object(root)
  }

  public static func request(for kind: TestPanelKind) throws -> ApprovalRequest {
    try ClaudeAdapter.parse(JSONEncoder().encode(payload(for: kind)))
  }

  private static let commandInput: JSONValue = .object([
    "command": .string("git push origin main"),
    "description": .string("Push the main branch to origin"),
  ])

  private static let commandSuggestions: JSONValue = .array([
    .object([
      "type": .string("addRules"),
      "rules": .array([
        .object([
          "toolName": .string("Bash"),
          "ruleContent": .string("git push origin *"),
        ])
      ]),
      "behavior": .string("allow"),
      "destination": .string("localSettings"),
    ])
  ])

  private static let questionInput: JSONValue = .object([
    "questions": .array([
      .object([
        "question": .string("Which date format should the report use?"),
        "header": .string("Format"),
        "options": .array([
          option("ISO 8601", description: "2026-09-28"),
          option("Day first", description: "28.09.2026"),
          option("Month first", description: "09.28.2026"),
        ]),
        "multiSelect": .bool(false),
      ]),
      .object([
        "question": .string("Which sections should the report include?"),
        "header": .string("Sections"),
        "options": .array([
          .object(["label": .string("Summary")]),
          .object(["label": .string("Charts")]),
          .object(["label": .string("Raw data")]),
        ]),
        "multiSelect": .bool(true),
      ]),
    ])
  ])

  private static let planInput: JSONValue = .object([
    "plan": .string(
      """
      # Add a changelog

      Start a `CHANGELOG.md` so every release says what changed.

      ## Steps

      1. Create `CHANGELOG.md` with an **Unreleased** section
      2. Add the entries for the latest release
      3. Link it from the README

      Nothing else changes.
      """)
  ])

  private static func option(_ label: String, description: String) -> JSONValue {
    .object(["label": .string(label), "description": .string(description)])
  }
}

public enum TestPanelLog {
  public static func start(_ kind: TestPanelKind) -> String {
    "test panel: start kind=\(kind.rawValue)"
  }

  public static func outcome(_ outcome: ApprovalOutcome, kind: TestPanelKind) -> String {
    "test panel: \(describe(outcome, kind: kind))"
  }

  public static func snooze(seconds: TimeInterval) -> String {
    "test panel: snoozed for \(DurationText.describe(seconds)), quiet time not started"
  }

  public static func refused(_ refusal: TestPanelRefusal) -> String {
    "test panel: refused (\(refusal.message))"
  }

  public static let closedForRealRequest = "test panel: closed for a real request"

  private static func describe(_ outcome: ApprovalOutcome, kind: TestPanelKind) -> String {
    switch outcome {
    case .noDecision:
      return "answered in chat"
    case .allow(_, let updatedPermissions):
      switch kind {
      case .command: return updatedPermissions.isEmpty ? "approved" : "approved with a suggestion"
      case .question: return "submitted"
      case .plan: return "approved"
      }
    case .deny(_, let interrupt):
      if kind == .plan {
        return "kept planning"
      }
      return interrupt ? "denied and stopped" : "denied"
    }
  }
}
