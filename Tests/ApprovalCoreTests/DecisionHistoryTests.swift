import Foundation
import Testing

@testable import ApprovalCore

@Suite struct DecisionHistoryTests {
  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("countersign-history-\(UUID().uuidString)")
  }

  private func history(in root: URL) -> DecisionHistory {
    DecisionHistory(
      file: root.appendingPathComponent("history.jsonl"),
      lockFile: root.appendingPathComponent("history.lock"))
  }

  private func entry(_ index: Int, answer: DecisionAnswer = .approved) -> DecisionHistoryEntry {
    DecisionHistoryEntry(
      date: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)), host: .claude,
      project: "ai-approval", tool: "Bash", title: "step \(index)", answer: answer)
  }

  private func request(
    tool: String = "Bash", input: JSONValue = .object([:]), kind: RequestKind
  ) -> ApprovalRequest {
    ApprovalRequest(
      host: .claude, sessionID: "s", cwd: "/work/ai-approval", permissionMode: nil,
      transcriptPath: nil, agentID: nil, agentType: nil, toolName: tool, toolInput: input,
      kind: kind)
  }

  private func permission(_ body: ToolBody) -> RequestKind {
    .permission(PermissionPrompt(body: body, suggestions: []))
  }

  @Test func appendedEntriesReadBackNewestFirst() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = history(in: root)

    try history.append(entry(1))
    try history.append(entry(2, answer: .denied))
    try history.append(entry(3, answer: .handOff))

    #expect(
      history.recent(limit: 10) == [
        entry(3, answer: .handOff), entry(2, answer: .denied), entry(1),
      ])
    #expect(history.recent(limit: 2) == [entry(3, answer: .handOff), entry(2, answer: .denied)])
    #expect(history.recent(limit: 0).isEmpty)
  }

  @Test func aMissingFileReadsAsEmpty() {
    #expect(history(in: temporaryRoot()).recent(limit: 10).isEmpty)
  }

  @Test func theFileTrimsToTheLastTwoHundredOnceItPassesTwoHundredFiftyLines() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = history(in: root)

    for index in 1...250 {
      try history.append(entry(index))
    }
    #expect(history.recent(limit: 1000).count == 250)

    try history.append(entry(251))
    let kept = history.recent(limit: 1000)
    #expect(kept.count == 200)
    #expect(kept.first == entry(251))
    #expect(kept.last == entry(52))
  }

  @Test func aMalformedLineIsSkipped() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = history(in: root)
    try history.append(entry(1))
    let file = root.appendingPathComponent("history.jsonl")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("not json\n{\"date\":1}\n".utf8))
    try handle.close()
    try history.append(entry(2))

    #expect(history.recent(limit: 10) == [entry(2), entry(1)])
  }

  @Test func clearEmptiesTheHistoryAndItCanGrowAgain() throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = history(in: root)
    try history.append(entry(1))

    try history.clear()
    #expect(history.recent(limit: 10).isEmpty)

    try history.append(entry(2))
    #expect(history.recent(limit: 10) == [entry(2)])
  }

  @Test func appendCreatesTheSupportDirectory() throws {
    let root = temporaryRoot().appendingPathComponent("nested")
    defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
    let history = history(in: root)

    try history.append(entry(1))

    #expect(history.recent(limit: 1) == [entry(1)])
  }

  @Test func historyLivesNextToTheOtherSupportFiles() {
    let paths = AppPaths(home: URL(fileURLWithPath: "/Users/dev"))
    let history = DecisionHistory(paths: paths)
    #expect(
      history.file.path == "/Users/dev/Library/Application Support/Countersign/history.jsonl")
    #expect(
      history.lockFile.path == "/Users/dev/Library/Application Support/Countersign/history.lock")
  }

  @Test func aBashTitleIsTheCommandsFirstLine() {
    let bash = request(
      kind: permission(.bash(command: "git status\ngit diff", description: nil)))
    #expect(DecisionTitle.title(for: bash) == "git status")
  }

  @Test func anEmptyBashCommandFallsBackToTheToolName() {
    let bash = request(kind: permission(.bash(command: "\n", description: nil)))
    #expect(DecisionTitle.title(for: bash) == "Bash")
  }

  @Test func editAndWriteTitlesAreTheFileName() {
    let edit = request(
      tool: "Edit",
      kind: permission(
        .edit(path: "/work/Sources/App.swift", oldString: "a", newString: "b", replaceAll: false)))
    let write = request(
      tool: "Write", kind: permission(.write(path: "/work/notes/plan.md", content: "x")))
    #expect(DecisionTitle.title(for: edit) == "App.swift")
    #expect(DecisionTitle.title(for: write) == "plan.md")
  }

  @Test func aMultiEditTitleIsTheFileNameFromItsInput() {
    let multiEdit = request(
      tool: "MultiEdit",
      input: .object(["file_path": .string("/work/Sources/Menu.swift")]),
      kind: permission(.json(.object(["file_path": .string("/work/Sources/Menu.swift")]))))
    #expect(DecisionTitle.title(for: multiEdit) == "Menu.swift")
  }

  @Test func anMCPTitleIsTheToolName() {
    let mcp = request(
      tool: "mcp__github__create_issue",
      kind: permission(.mcp(server: "github", tool: "create_issue", arguments: .object([:]))))
    #expect(DecisionTitle.title(for: mcp) == "create_issue")
  }

  @Test func aQuestionTitleIsItsFirstHeader() {
    let question = request(
      tool: "AskUserQuestion",
      kind: .questions([
        Question(question: "Which database?", header: "Database", options: [], multiSelect: false),
        Question(question: "Which cache?", header: "Cache", options: [], multiSelect: false),
      ]))
    #expect(DecisionTitle.title(for: question) == "Database")
  }

  @Test func aQuestionWithoutAHeaderUsesItsText() {
    let question = request(
      tool: "AskUserQuestion",
      kind: .questions([
        Question(question: "Which database?", header: nil, options: [], multiSelect: false)
      ]))
    #expect(DecisionTitle.title(for: question) == "Which database?")
  }

  @Test func aPlanTitleIsPlan() {
    let plan = request(
      tool: "ExitPlanMode", kind: .plan(PlanProposal(plan: "Do things", planFilePath: nil)))
    #expect(DecisionTitle.title(for: plan) == "Plan")
  }

  @Test func aCheckpointTitleNamesTheContextSize() {
    let prompt = ContextCheckpointPrompt(
      tokens: 240_000, level: .soft, ladder: [100_000], modelID: nil,
      handoffFile: "notes/handoff.md", notes: .default)
    let checkpoint = request(tool: "Context checkpoint", kind: .contextCheckpoint(prompt))
    #expect(DecisionTitle.title(for: checkpoint) == "Context at 240K")
  }

  @Test func otherToolsUseTheirToolName() {
    let fetch = request(
      tool: "WebFetch", kind: permission(.webFetch(url: "https://example.com", prompt: nil)))
    let patch = request(tool: "apply_patch", kind: permission(.patch(text: "*** Begin Patch")))
    #expect(DecisionTitle.title(for: fetch) == "WebFetch")
    #expect(DecisionTitle.title(for: patch) == "apply_patch")
  }

  @Test func titlesCutAtEightyCharactersWithAnEllipsis() {
    let exact = String(repeating: "a", count: 80)
    let long = String(repeating: "b", count: 81)
    let exactRequest = request(kind: permission(.bash(command: exact, description: nil)))
    let longRequest = request(kind: permission(.bash(command: long, description: nil)))

    #expect(DecisionTitle.title(for: exactRequest) == exact)
    let cut = DecisionTitle.title(for: longRequest)
    #expect(cut.count == 80)
    #expect(cut == String(repeating: "b", count: 79) + "…")
  }

  @Test func anEntryBuiltFromARequestCarriesItsIdentity() {
    let bash = request(kind: permission(.bash(command: "ls", description: nil)))
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let built = DecisionHistoryEntry(request: bash, answer: .denied, date: date)
    #expect(
      built
        == DecisionHistoryEntry(
          date: date, host: .claude, project: "ai-approval", tool: "Bash", title: "ls",
          answer: .denied))
  }

  @Test func answersMapFromOutcomesAndCheckpointChoices() {
    #expect(
      DecisionAnswer.answer(for: .allowAsIs, checkpointChoice: nil, isCheckpoint: false)
        == .approved)
    #expect(
      DecisionAnswer.answer(
        for: .deny(message: "no", interrupt: false), checkpointChoice: nil, isCheckpoint: false)
        == .denied)
    #expect(
      DecisionAnswer.answer(for: .noDecision, checkpointChoice: nil, isCheckpoint: false)
        == .answeredInChat)
    #expect(
      DecisionAnswer.answer(for: .noDecision, checkpointChoice: nil, isCheckpoint: true)
        == .dismissed)
    #expect(
      DecisionAnswer.answer(
        for: .noDecision, checkpointChoice: .continueWorking, isCheckpoint: true) == .continued)
    #expect(
      DecisionAnswer.answer(
        for: .addContext("x"), checkpointChoice: .compactAfterStep, isCheckpoint: true)
        == .compactAfterStep)
    #expect(
      DecisionAnswer.answer(for: .addContext("x"), checkpointChoice: .handOff, isCheckpoint: true)
        == .handOff)
    #expect(
      DecisionAnswer.answer(
        for: .noDecision, checkpointChoice: .notThisSession, isCheckpoint: true)
        == .notThisSession)
  }
}
