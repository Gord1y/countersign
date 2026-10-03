import Testing

@testable import ApprovalCore

private let stablePath = "/opt/homebrew/bin/countersign"
private let resolvedPath = "/opt/homebrew/Cellar/countersign/0.1.0/bin/countersign"

private func missingHost(_ host: Host) -> Doctor.HostInput {
  Doctor.HostInput(
    host: host, directoryPath: "/missing/\(host.rawValue)",
    filePath: "/missing/\(host.rawValue)/file.json", directoryExists: false, fileState: .missing,
    executableChecks: [:])
}

private func baseInput(
  hosts: [Doctor.HostInput],
  configFileExists: Bool = false,
  configLogLines: [String] = [],
  liveTicketCount: Int = 0,
  pauseState: PauseState = .active,
  quietUntilDescription: String? = nil,
  logFileSize: Int? = nil,
  contextCheckpointsEnabled: Bool = false
) -> Doctor.Input {
  Doctor.Input(
    version: "0.1.0",
    resolvedExecutablePath: resolvedPath,
    stableExecutablePath: stablePath,
    hosts: hosts,
    configPath: "/config/countersign/config.json",
    configFileExists: configFileExists,
    configLogLines: configLogLines,
    queueDirectoryPath: "/support/queue",
    liveTicketCount: liveTicketCount,
    pauseState: pauseState,
    quietUntilDescription: quietUntilDescription,
    logFilePath: "/logs/countersign.log",
    logFileSize: logFileSize, contextCheckpointsEnabled: contextCheckpointsEnabled)
}

private func codexEntryJSON(command: String) -> [UInt8] {
  let text = """
    {
      "hooks": {
        "PermissionRequest": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "\(command)",
                "timeout": 3600,
                "statusMessage": "Waiting for the approval panel"
              }
            ]
          }
        ]
      }
    }
    """
  return Array(text.utf8)
}

private func entryJSON(command: String, timeout: String? = "3600") -> [UInt8] {
  let timeoutMember = timeout.map { ",\n            \"timeout\": \($0)" } ?? ""
  let text = """
    {
      "hooks": {
        "PermissionRequest": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "\(command)"\(timeoutMember)
              }
            ]
          }
        ]
      }
    }
    """
  return Array(text.utf8)
}

@Suite struct DoctorTests {
  @Test func reportsTheVersionLineFirst() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), missingHost(.codex)]))
    #expect(
      lines.first
        == DoctorLine(
          status: .info, check: "version",
          detail: "countersign 0.1.0, running at \(resolvedPath), setup would write \(stablePath)")
    )
  }

  @Test func hostNotInstalledWhenItsDirectoryIsMissing() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(status: .info, check: "claude", detail: "not installed (/missing/claude)")))
  }

  @Test func hostFileMissingWarns() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail: "/missing/claude/file.json is missing, run countersign setup")))
  }

  @Test func hostFileUnreadableFails() {
    var host = missingHost(.claude)
    host.directoryExists = true
    host.fileState = .unreadable("permission denied")
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .fail, check: "claude",
          detail: "/missing/claude/file.json could not be read: permission denied")))
  }

  @Test func hostFileBlankWarnsLikeAMissingOne() {
    var host = missingHost(.claude)
    host.directoryExists = true
    host.fileState = .bytes(Array("   \n".utf8))
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail: "/missing/claude/file.json is empty, run countersign setup")))
  }

  @Test func hostFileInvalidJSONFails() {
    var host = missingHost(.claude)
    host.directoryExists = true
    host.fileState = .bytes(Array("{not json".utf8))
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    let line = lines.first { $0.check == "claude" }
    #expect(line?.status == .fail)
    #expect(line?.detail.hasPrefix("/missing/claude/file.json is not valid JSON:") == true)
  }

  @Test func hostWithNoEntryWarns() {
    var host = missingHost(.claude)
    host.directoryExists = true
    host.fileState = .bytes(Array("{}".utf8))
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail: "no countersign entry in /missing/claude/file.json, run countersign setup")))
  }

  @Test func healthyEntryReportsOK() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let command = "\(stablePath) hook --host claude"
    host.fileState = .bytes(entryJSON(command: command))
    host.executableChecks = [stablePath: true]
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    let claudeLines = lines.filter { $0.check == "claude" }
    #expect(claudeLines.count == 1)
    #expect(claudeLines.first?.status == .ok)
    #expect(claudeLines.first?.detail == "entry: \(stablePath), timeout 3600s")
  }

  @Test func entryWithADriftedPathWarns() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let command = "\(resolvedPath) hook --host claude"
    host.fileState = .bytes(entryJSON(command: command))
    host.executableChecks = [resolvedPath: true]
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail:
            "entry: \(resolvedPath) differs from the stable path \(stablePath), run countersign setup"
        )))
  }

  @Test func entryWithAMissingExecutableFails() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let command = "\(stablePath) hook --host claude"
    host.fileState = .bytes(entryJSON(command: command))
    host.executableChecks = [stablePath: false]
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .fail, check: "claude",
          detail: "entry: \(stablePath) does not exist or is not executable")))
  }

  @Test func entryWithAnUncheckedExecutableFails() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let command = "\(stablePath) hook --host claude"
    host.fileState = .bytes(entryJSON(command: command))
    host.executableChecks = [:]
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .fail, check: "claude",
          detail: "entry: \(stablePath) does not exist or is not executable")))
  }

  @Test func entryWithALowTimeoutWarns() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let command = "\(stablePath) hook --host claude"
    host.fileState = .bytes(entryJSON(command: command, timeout: "300"))
    host.executableChecks = [stablePath: true]
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail:
            "entry: timeout is 300s, below 600s; a short hook timeout can kill the wait for a person"
        )))
  }

  @Test func entryWithNoTimeoutWarns() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let command = "\(stablePath) hook --host claude"
    host.fileState = .bytes(entryJSON(command: command, timeout: nil))
    host.executableChecks = [stablePath: true]
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail:
            "entry: timeout is not set, below 600s; a short hook timeout can kill the wait for a person"
        )))
  }

  @Test func entryWithExtraArgumentsWarns() {
    var host = missingHost(.claude)
    host.directoryExists = true
    let command = "\(stablePath) hook --host claude --verbose"
    host.fileState = .bytes(entryJSON(command: command))
    host.executableChecks = [stablePath: true]
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(
      lines.filter { $0.check == "claude" } == [
        DoctorLine(
          status: .warn, check: "claude",
          detail:
            "entry: arguments hook --host claude --verbose differ from hook --host claude, run countersign setup"
        )
      ])
  }

  @Test func entryForAnotherHostOrWithNoHostWarns() {
    var host = missingHost(.claude)
    host.directoryExists = true
    host.executableChecks = [stablePath: true]
    host.fileState = .bytes(entryJSON(command: "\(stablePath) hook --host codex"))
    #expect(
      Doctor.report(baseInput(hosts: [host, missingHost(.codex)])).contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail:
            "entry: arguments hook --host codex differ from hook --host claude, run countersign setup"
        )))
    host.fileState = .bytes(entryJSON(command: "\(stablePath) hook"))
    #expect(
      Doctor.report(baseInput(hosts: [host, missingHost(.codex)])).contains(
        DoctorLine(
          status: .warn, check: "claude",
          detail: "entry: arguments hook differ from hook --host claude, run countersign setup")))
  }

  @Test func codexNotWiredGetsNoFollowUpLine() {
    var host = missingHost(.codex)
    host.directoryExists = true
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), host]))
    #expect(!lines.contains { $0.check == "codex" && $0.status != .warn })
  }

  @Test func codexNotInstalledGetsNoFollowUpLine() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), missingHost(.codex)]))
    #expect(lines.filter { $0.check == "codex" }.count == 1)
    #expect(
      lines.contains(
        DoctorLine(status: .info, check: "codex", detail: "not installed (/missing/codex)")))
  }

  @Test func codexWiredWithUnknownTrustGetsTheNextStepLine() {
    var host = missingHost(.codex)
    host.directoryExists = true
    host.fileState = .bytes(codexEntryJSON(command: "\(stablePath) hook --host codex"))
    host.executableChecks = [stablePath: true]
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), host]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .info, check: "codex",
          detail:
            "cannot tell whether Codex trusts Countersign's hook. \(AgentFollowUps.codexNextStep)"
        )))
  }

  @Test func codexWiredWithAMarkedTrustRecordGetsTheMarkedLine() {
    var host = missingHost(.codex)
    host.directoryExists = true
    host.fileState = .bytes(codexEntryJSON(command: "\(stablePath) hook --host codex"))
    host.executableChecks = [stablePath: true]
    var input = baseInput(hosts: [missingHost(.claude), host])
    input.codexHookTrustRecord = CodexHookTrustRecord(
      hookKey: "\(host.filePath):permission_request:0:0",
      command: "\(stablePath) hook --host codex", markedDone: true)
    let lines = Doctor.report(input)
    #expect(
      lines.contains(
        DoctorLine(
          status: .ok, check: "codex", detail: "you marked Countersign's hook as trusted in Codex")
      ))
  }

  @Test(arguments: [
    (CodexHashAtWrite.absent, "sha256:new", DoctorStatus.ok, "Codex trusts Countersign's hook"),
    (
      CodexHashAtWrite.absent, nil, DoctorStatus.warn,
      "Codex has not trusted Countersign's hook yet. \(AgentFollowUps.codexNextStep)"
    ),
    (
      CodexHashAtWrite.stored("sha256:old"), "sha256:old", DoctorStatus.info,
      "cannot tell whether Codex trusts Countersign's hook. \(AgentFollowUps.codexNextStep)"
    ),
    (
      CodexHashAtWrite.unread, "sha256:new", DoctorStatus.info,
      "cannot tell whether Codex trusts Countersign's hook. \(AgentFollowUps.codexNextStep)"
    ),
  ])
  func codexWiredReadsTheTrustCodexStored(
    hashAtWrite: CodexHashAtWrite, stored: String?, status: DoctorStatus, detail: String
  ) {
    var host = missingHost(.codex)
    host.directoryExists = true
    host.fileState = .bytes(codexEntryJSON(command: "\(stablePath) hook --host codex"))
    host.executableChecks = [stablePath: true]
    let key = "\(host.filePath):permission_request:0:0"
    var input = baseInput(hosts: [missingHost(.claude), host])
    input.codexHookTrustRecord = CodexHookTrustRecord(
      hookKey: key, command: "\(stablePath) hook --host codex", hashAtWrite: hashAtWrite)
    input.codexConfigFile = .bytes(
      Array(
        (stored.map { "[hooks.state.\"\(key)\"]\ntrusted_hash = \"\($0)\"\n" } ?? "model = \"o3\"\n")
          .utf8))
    let lines = Doctor.report(input)
    #expect(
      lines.filter { $0.check == "codex" }.last
        == DoctorLine(status: status, check: "codex", detail: detail))
  }

  @Test func codexWiredAfterAHookBeforeOursWasRemovedGetsTheReason() {
    var host = missingHost(.codex)
    host.directoryExists = true
    host.fileState = .bytes(codexEntryJSON(command: "\(stablePath) hook --host codex"))
    host.executableChecks = [stablePath: true]
    var input = baseInput(hosts: [missingHost(.claude), host])
    input.codexHookTrustRecord = CodexHookTrustRecord(
      hookKey: "\(host.filePath):permission_request:1:0",
      command: "\(stablePath) hook --host codex", learnedHash: "sha256:ours")
    input.codexConfigFile = .bytes(Array("model = \"o3\"\n".utf8))
    let lines = Doctor.report(input)
    #expect(
      lines.filter { $0.check == "codex" }.last
        == DoctorLine(
          status: .warn, check: "codex",
          detail:
            "Codex asks again because a hook before Countersign's was removed. \(AgentFollowUps.codexNextStep)"
        ))
  }

  @Test func codexWiredWithAStaleTrustRecordGetsTheNextStepLine() {
    var host = missingHost(.codex)
    host.directoryExists = true
    host.fileState = .bytes(codexEntryJSON(command: "\(stablePath) hook --host codex"))
    host.executableChecks = [stablePath: true]
    var input = baseInput(hosts: [missingHost(.claude), host])
    input.codexHookTrustRecord = CodexHookTrustRecord(hookKey: "stale", command: "stale")
    let lines = Doctor.report(input)
    #expect(
      lines.contains(
        DoctorLine(
          status: .info, check: "codex",
          detail:
            "cannot tell whether Codex trusts Countersign's hook. \(AgentFollowUps.codexNextStep)"
        )))
  }

  @Test func configMissingIsInfo() {
    let lines = Doctor.report(
      baseInput(hosts: [missingHost(.claude), missingHost(.codex)], configFileExists: false))
    #expect(
      lines.contains(
        DoctorLine(
          status: .info, check: "config",
          detail: "/config/countersign/config.json: no config file, using defaults")))
  }

  @Test func configParsedCleanlyIsOK() {
    let lines = Doctor.report(
      baseInput(hosts: [missingHost(.claude), missingHost(.codex)], configFileExists: true))
    #expect(
      lines.contains(
        DoctorLine(
          status: .ok, check: "config",
          detail: "/config/countersign/config.json: parsed cleanly")))
  }

  @Test func configParserLinesWarn() {
    let lines = Doctor.report(
      baseInput(
        hosts: [missingHost(.claude), missingHost(.codex)], configFileExists: true,
        configLogLines: ["armDelay: not a number, using default 0.5"]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "config", detail: "armDelay: not a number, using default 0.5")))
  }

  @Test func rulesLineSaysNoneWithoutRules() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), missingHost(.codex)]))
    #expect(lines.contains(DoctorLine(status: .info, check: "rules", detail: "none")))
  }

  @Test func rulesLineCountsAllowAndDenyRules() {
    var input = baseInput(hosts: [missingHost(.claude), missingHost(.codex)])
    input.rules = [
      ApprovalRule(decision: .allow, tool: "Read"),
      ApprovalRule(decision: .deny, command: "rm *"),
      ApprovalRule(decision: .allow, command: "pnpm lint"),
    ]
    #expect(
      Doctor.report(input).contains(
        DoctorLine(status: .ok, check: "rules", detail: "3 (2 allow, 1 deny)")))
  }

  @Test func queueReportsTheLiveTicketCount() {
    let lines = Doctor.report(
      baseInput(hosts: [missingHost(.claude), missingHost(.codex)], liveTicketCount: 2))
    #expect(
      lines.contains(
        DoctorLine(status: .info, check: "queue", detail: "/support/queue: 2 live ticket(s)")))
  }

  @Test func statePausedWithQuietTime() {
    let lines = Doctor.report(
      baseInput(
        hosts: [missingHost(.claude), missingHost(.codex)], pauseState: .paused,
        quietUntilDescription: "14:30"))
    #expect(
      lines.contains(
        DoctorLine(status: .info, check: "state", detail: "paused, quiet until 14:30")))
  }

  @Test func statePausedUntilCountersignOpens() {
    let lines = Doctor.report(
      baseInput(
        hosts: [missingHost(.claude), missingHost(.codex)], pauseState: .pausedUntilAppOpens))
    #expect(
      lines.contains(
        DoctorLine(
          status: .info, check: "state", detail: "paused until Countersign opens, quiet off")))
  }

  @Test func stateActiveWithQuietOff() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), missingHost(.codex)]))
    #expect(
      lines.contains(DoctorLine(status: .info, check: "state", detail: "active, quiet off")))
  }

  @Test func logReportsItsSize() {
    let lines = Doctor.report(
      baseInput(hosts: [missingHost(.claude), missingHost(.codex)], logFileSize: 4096))
    #expect(
      lines.contains(
        DoctorLine(status: .info, check: "log", detail: "/logs/countersign.log: 4096 byte(s)")))
  }

  @Test func logMissingSaysSo() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), missingHost(.codex)]))
    #expect(
      lines.contains(
        DoctorLine(status: .info, check: "log", detail: "/logs/countersign.log: not created yet")))
  }

  @Test func exitCodeIsOneWhenAnyLineFails() {
    var host = missingHost(.claude)
    host.directoryExists = true
    host.fileState = .bytes(Array("{not json".utf8))
    let lines = Doctor.report(baseInput(hosts: [host, missingHost(.codex)]))
    #expect(Doctor.exitCode(for: lines) == 1)
  }

  @Test func exitCodeIsZeroWhenNothingFails() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.claude), missingHost(.codex)]))
    #expect(Doctor.exitCode(for: lines) == 0)
  }

  @Test func executablePathsListsOnePerEntry() {
    let command = "\(stablePath) hook --host claude"
    let bytes = entryJSON(command: command)
    #expect(Doctor.executablePaths(inHookConfig: bytes, host: .claude) == [stablePath])
    #expect(Doctor.executablePaths(inHookConfig: bytes, host: .cursor) == [])
  }

  @Test func executablePathsIsEmptyForInvalidJSON() {
    #expect(Doctor.executablePaths(inHookConfig: Array("{not json".utf8), host: .claude) == [])
  }

  @Test func executablePathsIsEmptyWithNoEntry() {
    #expect(Doctor.executablePaths(inHookConfig: Array("{}".utf8), host: .claude) == [])
  }

  @Test func executablePathsListsBothCursorEvents() {
    let bytes = cursorJSON(shell: [cursorEntry()], mcp: [cursorEntry(path: resolvedPath)])
    #expect(
      Doctor.executablePaths(inHookConfig: bytes, host: .cursor) == [stablePath, resolvedPath])
  }

  @Test func healthyCursorEntriesReportOKPerEventAndTheGoodToKnowLine() {
    let lines = Doctor.report(
      baseInput(hosts: [cursorHost(cursorJSON(shell: [cursorEntry()], mcp: [cursorEntry()]))]))
    #expect(
      lines.filter { $0.check == "cursor" } == [
        DoctorLine(
          status: .ok, check: "cursor",
          detail: "beforeShellExecution entry: \(stablePath), timeout 3600s"),
        DoctorLine(
          status: .ok, check: "cursor",
          detail: "beforeMCPExecution entry: \(stablePath), timeout 3600s"),
        DoctorLine(status: .info, check: "cursor", detail: AgentFollowUps.cursorGoodToKnow),
      ])
  }

  @Test func cursorWithNoEntryWarns() {
    let lines = Doctor.report(baseInput(hosts: [cursorHost(Array("{\"version\": 1}".utf8))]))
    #expect(
      lines.filter { $0.check == "cursor" } == [
        DoctorLine(
          status: .warn, check: "cursor",
          detail: "no countersign entry in /home/.cursor/hooks.json, run countersign setup")
      ])
  }

  @Test func cursorEntryMissingFromOneEventWarns() {
    let lines = Doctor.report(
      baseInput(hosts: [cursorHost(cursorJSON(shell: [cursorEntry()], mcp: []))]))
    #expect(
      lines.filter { $0.check == "cursor" } == [
        DoctorLine(
          status: .warn, check: "cursor",
          detail:
            "no countersign entry under hooks.beforeMCPExecution in /home/.cursor/hooks.json, run countersign setup"
        ),
        DoctorLine(
          status: .ok, check: "cursor",
          detail: "beforeShellExecution entry: \(stablePath), timeout 3600s"),
      ])
  }

  @Test func cursorEntriesAreCheckedLikeTheOtherHosts() {
    let bytes = cursorJSON(
      shell: [cursorEntry(path: resolvedPath), cursorEntry(path: "/gone/countersign")],
      mcp: [cursorEntry(timeout: "30")])
    let lines = Doctor.report(
      baseInput(hosts: [cursorHost(bytes, checks: [stablePath: true, resolvedPath: true])]))
    let cursorLines = lines.filter { $0.check == "cursor" }
    #expect(
      cursorLines == [
        DoctorLine(
          status: .warn, check: "cursor",
          detail:
            "beforeShellExecution entry 1: \(resolvedPath) differs from the stable path \(stablePath), run countersign setup"
        ),
        DoctorLine(
          status: .warn, check: "cursor",
          detail:
            "beforeShellExecution entry 2: /gone/countersign differs from the stable path \(stablePath), run countersign setup"
        ),
        DoctorLine(
          status: .fail, check: "cursor",
          detail:
            "beforeShellExecution entry 2: /gone/countersign does not exist or is not executable"
        ),
        DoctorLine(
          status: .warn, check: "cursor",
          detail:
            "beforeMCPExecution entry: timeout is 30s, below 600s; a short hook timeout can kill the wait for a person"
        ),
      ])
    #expect(Doctor.exitCode(for: lines) == 1)
  }

  @Test func healthyAntigravityHookReportsOKAndTheGoodToKnowLine() {
    let lines = Doctor.report(baseInput(hosts: [antigravityHost(antigravityJSON())]))
    #expect(
      lines.filter { $0.check == "antigravity" } == [
        DoctorLine(
          status: .ok, check: "antigravity", detail: "entry: \(stablePath), timeout 3600s"),
        DoctorLine(
          status: .info, check: "antigravity", detail: AgentFollowUps.antigravityGoodToKnow),
      ])
    #expect(Doctor.exitCode(for: lines) == 0)
  }

  @Test func antigravityWithoutOurNamedHookWarns() {
    let lines = Doctor.report(baseInput(hosts: [antigravityHost(Array("{\"audit\": {}}".utf8))]))
    #expect(
      lines.contains(
        DoctorLine(
          status: .warn, check: "antigravity",
          detail:
            "no countersign entry in /home/.gemini/config/hooks.json, run countersign setup")))
  }

  @Test func antigravityHookInAnotherShapeWarns() {
    let lines = Doctor.report(
      baseInput(hosts: [antigravityHost(antigravityJSON(matcher: "run_command"))]))
    #expect(
      lines.filter { $0.check == "antigravity" && $0.status != .info } == [
        DoctorLine(
          status: .warn, check: "antigravity",
          detail:
            "the countersign hook in /home/.gemini/config/hooks.json is not in the shape setup writes, run countersign setup; Antigravity ignores the whole file when any part of it is invalid"
        )
      ])
  }

  @Test func antigravityFileThatDoesNotParseSaysNothingInItRuns() {
    let lines = Doctor.report(baseInput(hosts: [antigravityHost(Array("{\"audit\": {},}".utf8))]))
    let line = lines.first { $0.check == "antigravity" }
    #expect(line?.status == .fail)
    #expect(
      line?.detail.hasPrefix("/home/.gemini/config/hooks.json is not valid JSON: not valid JSON at")
        == true)
    #expect(
      line?.detail.hasSuffix(
        "; Antigravity ignores the whole file when any part of it is invalid") == true)
    var claude = missingHost(.claude)
    claude.directoryExists = true
    claude.fileState = .bytes(Array("{not json".utf8))
    let claudeLine = Doctor.report(baseInput(hosts: [claude])).first { $0.check == "claude" }
    #expect(claudeLine?.detail.contains("Antigravity") == false)
  }

  @Test func antigravityEntryIsCheckedLikeTheOtherHosts() {
    let bytes = antigravityJSON(path: resolvedPath, timeout: "30")
    let lines = Doctor.report(
      baseInput(hosts: [antigravityHost(bytes, checks: [resolvedPath: false])]))
    #expect(
      lines.filter { $0.check == "antigravity" && $0.status != .info } == [
        DoctorLine(
          status: .warn, check: "antigravity",
          detail:
            "entry: \(resolvedPath) differs from the stable path \(stablePath), run countersign setup"
        ),
        DoctorLine(
          status: .fail, check: "antigravity",
          detail: "entry: \(resolvedPath) does not exist or is not executable"),
        DoctorLine(
          status: .warn, check: "antigravity",
          detail:
            "entry: timeout is 30s, below 600s; a short hook timeout can kill the wait for a person"
        ),
      ])
    #expect(Doctor.executablePaths(inHookConfig: bytes, host: .antigravity) == [resolvedPath])
    #expect(Doctor.executablePaths(inHookConfig: bytes, host: .cursor) == [])
  }

  @Test func antigravityNotInstalledSkipsTheAllowNote() {
    let lines = Doctor.report(baseInput(hosts: [missingHost(.antigravity)]))
    #expect(
      lines.filter { $0.check == "antigravity" } == [
        DoctorLine(
          status: .info, check: "antigravity", detail: "not installed (/missing/antigravity)")
      ])
  }
}

private func antigravityJSON(
  path: String = stablePath, matcher: String = "*", timeout: String = "3600"
) -> [UInt8] {
  let text = """
    {"countersign": {"PreToolUse": [{"matcher": "\(matcher)", "hooks": [
      {"type": "command", "command": "\(path) hook --host antigravity", "timeout": \(timeout)}
    ]}]}}
    """
  return Array(text.utf8)
}

private func antigravityHost(_ bytes: [UInt8], checks: [String: Bool] = [stablePath: true])
  -> Doctor.HostInput
{
  Doctor.HostInput(
    host: .antigravity, directoryPath: "/home/.gemini/antigravity-cli",
    filePath: "/home/.gemini/config/hooks.json", directoryExists: true,
    fileState: .bytes(bytes), executableChecks: checks)
}

private func cursorEntry(path: String = stablePath, timeout: String = "3600") -> String {
  "{\"command\": \"\(path) hook --host cursor\", \"timeout\": \(timeout)}"
}

private func cursorJSON(shell: [String], mcp: [String]) -> [UInt8] {
  let text = """
    {"version": 1, "hooks": {
      "beforeShellExecution": [\(shell.joined(separator: ", "))],
      "beforeMCPExecution": [\(mcp.joined(separator: ", "))]
    }}
    """
  return Array(text.utf8)
}

private func cursorHost(_ bytes: [UInt8], checks: [String: Bool] = [stablePath: true])
  -> Doctor.HostInput
{
  Doctor.HostInput(
    host: .cursor, directoryPath: "/home/.cursor", filePath: "/home/.cursor/hooks.json",
    directoryExists: true, fileState: .bytes(bytes), executableChecks: checks)
}

private let claudeFilePath = "/missing/claude/file.json"

private func claudeContextLines(
  promptEntry: String?, enabled: Bool, checks: [String: Bool] = [stablePath: true]
)
  -> [DoctorLine]
{
  let prompt = promptEntry.map { ", \"UserPromptSubmit\": [{\"hooks\": [\($0)]}]" } ?? ""
  let text = """
    {"hooks": {"PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "\(stablePath) hook --host claude", "timeout": 3600}]}]\(prompt)}}
    """
  var host = missingHost(.claude)
  host.directoryExists = true
  host.fileState = .bytes(Array(text.utf8))
  host.executableChecks = checks
  return Doctor.report(
    baseInput(hosts: [host, missingHost(.codex)], contextCheckpointsEnabled: enabled)
  ).filter { $0.check == "claude context" }
}

private func promptHook(
  command: String = "\(stablePath) hook --host claude", async: String? = "true",
  timeout: String? = "3600"
) -> String {
  var members = ["\"type\": \"command\"", "\"command\": \"\(command)\""]
  if let async { members.append("\"async\": \(async)") }
  if let timeout { members.append("\"timeout\": \(timeout)") }
  return "{\(members.joined(separator: ", "))}"
}

@Suite struct DoctorContextTests {
  @Test func warnsWhenCheckpointsAreOnButThereIsNoEntry() {
    #expect(
      claudeContextLines(promptEntry: nil, enabled: true) == [
        DoctorLine(
          status: .warn, check: "claude context",
          detail:
            "context checkpoints are on in config.json, but \(claudeFilePath) has no UserPromptSubmit entry of Countersign's; turn Context checkpoints off and on again in countersign settings"
        )
      ])
  }

  @Test func warnsWhenCheckpointsAreOffButTheEntryRemains() {
    #expect(
      claudeContextLines(promptEntry: promptHook(), enabled: false) == [
        DoctorLine(
          status: .warn, check: "claude context",
          detail:
            "\(claudeFilePath) still has Countersign's UserPromptSubmit entry although context checkpoints are off; turning Context checkpoints off in countersign settings removes it"
        )
      ])
  }

  @Test func warnsWhenTheEntryIsNotAsync() {
    for async in [nil, "false", "\"true\""] {
      #expect(
        claudeContextLines(promptEntry: promptHook(async: async), enabled: true) == [
          DoctorLine(
            status: .warn, check: "claude context",
            detail:
              "Countersign's UserPromptSubmit entry in \(claudeFilePath) is not async, so every prompt waits for the checkpoint panel; run countersign setup"
          )
        ])
    }
  }

  @Test func reportsOKWhenEnabledAndTheEntryIsFine() {
    #expect(
      claudeContextLines(promptEntry: promptHook(), enabled: true) == [
        DoctorLine(
          status: .ok, check: "claude context",
          detail: "UserPromptSubmit entry in \(claudeFilePath), async")
      ])
  }

  @Test func staysSilentWhenDisabledWithoutAnEntry() {
    #expect(claudeContextLines(promptEntry: nil, enabled: false).isEmpty)
  }

  @Test func reusesTheEntryChecksWithTheUserPromptSubmitLabel() {
    let lines = claudeContextLines(
      promptEntry: promptHook(command: "/x/countersign hook --host claude", timeout: nil),
      enabled: true, checks: [stablePath: true, "/x/countersign": false])
    #expect(
      lines.map(\.detail) == [
        "UserPromptSubmit entry: /x/countersign differs from the stable path \(stablePath), run countersign setup",
        "UserPromptSubmit entry: /x/countersign does not exist or is not executable",
        "UserPromptSubmit entry: timeout is not set, below 600s; a short hook timeout can kill the wait for a person",
      ])
  }
}

private func claudeWaitingLines(
  stopEntry: String?, enabled: Bool, checks: [String: Bool] = [stablePath: true]
) -> [DoctorLine] {
  let stop = stopEntry.map { ", \"Stop\": [{\"hooks\": [\($0)]}]" } ?? ""
  let text = """
    {"hooks": {"PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "\(stablePath) hook --host claude", "timeout": 3600}]}]\(stop)}}
    """
  var host = missingHost(.claude)
  host.directoryExists = true
  host.fileState = .bytes(Array(text.utf8))
  host.executableChecks = checks
  var input = baseInput(hosts: [host, missingHost(.codex)])
  input.waitingNoticesEnabled = enabled
  return Doctor.report(input).filter { $0.check == "claude waiting" }
}

private func stopHook(
  command: String = "\(stablePath) hook --host claude --event waiting", async: String? = "true",
  timeout: String? = "30"
) -> String {
  promptHook(command: command, async: async, timeout: timeout)
}

@Suite struct DoctorWaitingTests {
  @Test func warnsWhenNoticesAreOnButThereIsNoEntry() {
    #expect(
      claudeWaitingLines(stopEntry: nil, enabled: true) == [
        DoctorLine(
          status: .warn, check: "claude waiting",
          detail:
            "waiting-agent notices are on, but \(claudeFilePath) has no Stop entry of Countersign's; run countersign setup, or Update in Settings ▸ Agents"
        )
      ])
  }

  @Test func warnsWhenNoticesAreOffButTheEntryRemains() {
    #expect(
      claudeWaitingLines(stopEntry: stopHook(), enabled: false) == [
        DoctorLine(
          status: .warn, check: "claude waiting",
          detail:
            "\(claudeFilePath) still has Countersign's Stop entry although waiting-agent notices are off; turning Waiting-agent notices off in countersign settings removes it"
        )
      ])
  }

  @Test func warnsWhenTheEntryIsNotAsync() {
    for async in [nil, "false", "\"true\""] {
      #expect(
        claudeWaitingLines(stopEntry: stopHook(async: async), enabled: true) == [
          DoctorLine(
            status: .warn, check: "claude waiting",
            detail:
              "Countersign's Stop entry in \(claudeFilePath) is not async, so every turn end waits for it; run countersign setup"
          )
        ])
    }
  }

  @Test func reportsOKWhenEnabledAndTheEntryIsFine() {
    #expect(
      claudeWaitingLines(stopEntry: stopHook(), enabled: true) == [
        DoctorLine(
          status: .ok, check: "claude waiting", detail: "Stop entry in \(claudeFilePath), async")
      ])
  }

  @Test func staysSilentWhenDisabledWithoutAnEntry() {
    #expect(claudeWaitingLines(stopEntry: nil, enabled: false).isEmpty)
  }

  @Test func doesNotDemandTheLongTimeoutOfTheApprovalEntry() {
    let lines = claudeWaitingLines(
      stopEntry: stopHook(command: "/x/countersign hook --host claude", timeout: nil),
      enabled: true, checks: [stablePath: true, "/x/countersign": false])
    #expect(
      lines.map(\.detail) == [
        "Stop entry: /x/countersign differs from the stable path \(stablePath), run countersign setup",
        "Stop entry: /x/countersign does not exist or is not executable",
        "Stop entry: arguments hook --host claude differ from hook --host claude --event waiting, run countersign setup",
      ])
  }
}

private func codexWaitingLines(
  trust: CodexHookTrustRecord?, config: Doctor.FileState
) -> [DoctorLine] {
  let text = """
    {"hooks": {"PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "\(stablePath) hook --host codex", "timeout": 3600}]}], "Stop": [{"hooks": [{"type": "command", "command": "\(stablePath) hook --host codex --event waiting", "timeout": 30}]}]}}
    """
  var host = missingHost(.codex)
  host.directoryExists = true
  host.fileState = .bytes(Array(text.utf8))
  host.executableChecks = [stablePath: true]
  var input = baseInput(hosts: [missingHost(.claude), host])
  input.waitingNoticesEnabled = true
  input.codexWaitingHookTrustRecord = trust
  input.codexConfigFile = config
  return Doctor.report(input).filter { $0.check == "codex waiting" }
}

private func cursorWaitingLines(stop: String?, enabled: Bool) -> [DoctorLine] {
  let stopText = stop.map { ", \"stop\": [\($0)]" } ?? ""
  let text = """
    {"version": 1, "hooks": {"beforeShellExecution": [{"command": "\(stablePath) hook --host cursor", "timeout": 3600}]\(stopText)}}
    """
  var host = missingHost(.cursor)
  host.directoryExists = true
  host.fileState = .bytes(Array(text.utf8))
  host.executableChecks = [stablePath: true]
  var input = baseInput(hosts: [missingHost(.claude), host])
  input.waitingNoticesEnabled = enabled
  return Doctor.report(input).filter { $0.check == "cursor waiting" }
}

@Suite struct DoctorOtherHostsWaitingTests {
  private let codexFilePath = "/missing/codex/file.json"
  private let cursorFilePath = "/missing/cursor/file.json"

  @Test func codexWarnsWhileCodexHasNotTrustedTheStopEntry() {
    let key = "\(codexFilePath):stop:0:0"
    let lines = codexWaitingLines(
      trust: CodexHookTrustRecord(
        hookKey: key, command: "\(stablePath) hook --host codex --event waiting",
        hashAtWrite: .absent),
      config: .bytes(Array("model = \"o3\"\n".utf8)))
    #expect(
      lines == [
        DoctorLine(
          status: .ok, check: "codex waiting", detail: "Stop entry in \(codexFilePath)"),
        DoctorLine(
          status: .warn, check: "codex waiting",
          detail:
            "Codex has not trusted Countersign's Stop entry yet; run /hooks in a Codex session and trust it"
        ),
      ])
  }

  @Test func codexSaysNothingExtraOnceCodexTrustsTheStopEntry() {
    let key = "\(codexFilePath):stop:0:0"
    let lines = codexWaitingLines(
      trust: CodexHookTrustRecord(
        hookKey: key, command: "\(stablePath) hook --host codex --event waiting",
        learnedHash: "sha256:stop"),
      config: .bytes(Array("[hooks.state.\"\(key)\"]\ntrusted_hash = \"sha256:stop\"\n".utf8)))
    #expect(
      lines == [
        DoctorLine(
          status: .ok, check: "codex waiting", detail: "Stop entry in \(codexFilePath)")
      ])
  }

  @Test func codexCannotTellWithoutARecord() {
    let lines = codexWaitingLines(trust: nil, config: .missing)
    #expect(
      lines.last
        == DoctorLine(
          status: .info, check: "codex waiting",
          detail:
            "cannot tell whether Codex trusts Countersign's Stop entry; run /hooks in a Codex session to check"
        ))
  }

  @Test func cursorReportsAFineEntryWithoutTheAsyncLine() {
    let entry =
      "{\"command\": \"\(stablePath) hook --host cursor --event waiting\", \"timeout\": 30}"
    #expect(
      cursorWaitingLines(stop: entry, enabled: true) == [
        DoctorLine(
          status: .ok, check: "cursor waiting", detail: "stop entry in \(cursorFilePath)")
      ])
  }

  @Test func cursorWarnsWhenNoticesAreOnButTheEntryIsMissing() {
    #expect(
      cursorWaitingLines(stop: nil, enabled: true) == [
        DoctorLine(
          status: .warn, check: "cursor waiting",
          detail:
            "waiting-agent notices are on, but \(cursorFilePath) has no stop entry of Countersign's; run countersign setup, or Update in Settings ▸ Agents"
        )
      ])
  }
}
