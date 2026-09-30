import Testing

@testable import ApprovalCore

@Suite struct PanelAnnouncementTests {
  private static func request(
    kind: RequestKind, tool: String = "Bash", agentType: String? = nil
  ) -> ApprovalRequest {
    ApprovalRequest(
      host: .claude, sessionID: "s", cwd: "/Users/me/work/countersign", permissionMode: nil,
      transcriptPath: nil, agentID: nil, agentType: agentType, toolName: tool, toolInput: .null,
      kind: kind)
  }

  private static let permission = RequestKind.permission(
    PermissionPrompt(body: .bash(command: "ls", description: nil), suggestions: []))

  @Test func permissionNamesHostProjectAndTool() {
    #expect(
      PanelAnnouncement.text(for: Self.request(kind: Self.permission))
        == "Claude Code, countersign: asks permission to use Bash")
  }

  @Test func subagentIsNamed() {
    #expect(
      PanelAnnouncement.text(for: Self.request(kind: Self.permission, agentType: "Explore"))
        == "Claude Code, countersign, subagent Explore: asks permission to use Bash")
  }

  @Test func questionsCountThemselves() {
    let question = Question(question: "Pick", header: nil, options: [], multiSelect: false)
    #expect(
      PanelAnnouncement.text(for: Self.request(kind: .questions([question])))
        == "Claude Code, countersign: asks a question")
    #expect(
      PanelAnnouncement.text(for: Self.request(kind: .questions([question, question])))
        == "Claude Code, countersign: asks 2 questions")
  }

  @Test func planIsProposed() {
    let plan = RequestKind.plan(PlanProposal(plan: "x", planFilePath: nil))
    #expect(
      PanelAnnouncement.text(for: Self.request(kind: plan))
        == "Claude Code, countersign: proposes a plan")
  }

  @Test func shortcutHintsSpeakTheKeys() {
    #expect(PanelAnnouncement.shortcutHint(for: "⏎") == "Shortcut: Return")
    #expect(PanelAnnouncement.shortcutHint(for: "⌘⏎") == "Shortcut: Command-Return")
    #expect(PanelAnnouncement.shortcutHint(for: "⌫") == "Shortcut: Delete")
    #expect(PanelAnnouncement.shortcutHint(for: "esc") == "Shortcut: Escape")
    #expect(PanelAnnouncement.shortcutHint(for: "1") == "Shortcut: 1")
  }

  @Test func diffLinesStartWithAddedOrRemovedAndNameTheirLine() {
    let added = NumberedLine(kind: .added, text: "let a = 1", oldNumber: nil, newNumber: 12)
    let removed = NumberedLine(kind: .removed, text: "let a = 0", oldNumber: 11, newNumber: nil)
    let context = NumberedLine(kind: .context, text: "", oldNumber: 3, newNumber: 4)
    #expect(
      DiffLineSpeech.label(for: added, showsNumbers: true) == "Added, line 12: let a = 1")
    #expect(
      DiffLineSpeech.label(for: removed, showsNumbers: true) == "Removed, line 11: let a = 0")
    #expect(DiffLineSpeech.label(for: context, showsNumbers: true) == "line 4: blank")
    #expect(DiffLineSpeech.label(for: context, showsNumbers: false) == "blank")
    #expect(DiffLineSpeech.label(for: added, showsNumbers: false) == "Added: let a = 1")
  }

  @Test func increasedContrastOrangeReadsOnBothCards() {
    let light = PanelContrast.increasedContrastOrangeLight
    let dark = PanelContrast.increasedContrastOrangeDark
    #expect(
      light.contrastRatio(with: PanelContrast.lightCardBackground)
        >= AccentPalette.minimumTextContrast)
    #expect(
      dark.contrastRatio(with: PanelContrast.darkCardBackground)
        >= AccentPalette.minimumTextContrast)
    #expect(
      PanelContrast.systemOrangeLight.contrastRatio(with: PanelContrast.lightCardBackground)
        < AccentPalette.minimumTextContrast)
  }
}
