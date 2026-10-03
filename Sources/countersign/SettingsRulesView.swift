import AppKit
import ApprovalCore
import SwiftUI

struct RulesSection: View {
  static let introMinWidth: CGFloat = 240

  let model: SettingsModel

  var body: some View {
    SettingsSection(.rules) {
      ConfigProblemMessage(model: model)
      SettingsGroup {
        VStack(alignment: .leading, spacing: 10) {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
              intro
                .frame(
                  minWidth: Self.introMinWidth, idealWidth: Self.introMinWidth,
                  maxWidth: .infinity, alignment: .leading)
              addButton
            }
            VStack(alignment: .leading, spacing: 10) {
              intro
              addButton
            }
          }
          RulesList(model: model)
          if let error = model.rulesError {
            InlineMessage(error, tone: .problem)
          }
          UnreadableRulesNotice(model: model)
        }
        .padding(SettingsMetrics.rowPadding)
      }
    }
  }

  private var intro: some View {
    Text(
      "Rules answer before any panel shows. Deny wins; a compound command is allowed only"
        + " when every part is."
    )
    .font(PanelTypography.secondary)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var addButton: some View {
    Button("Add Rule…") {
      RuleSheet.present(model: model, editing: nil, on: NSApp.keyWindow)
    }
    .buttonStyle(SecondaryButtonStyle())
    .fixedSize()
  }
}

private struct RulesList: View {
  static let emptyText =
    "No rules yet. Add one here, or choose Approve ▾ ▸ Always allow on a panel from Cursor,"
    + " Codex or Antigravity."

  let model: SettingsModel

  var body: some View {
    if model.rules.isEmpty {
      Text(Self.emptyText)
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(model.rules.enumerated()), id: \.offset) { _, rule in
          RuleRow(rule: rule, model: model)
        }
      }
    }
  }
}

private struct RuleRow: View {
  let rule: ApprovalRule
  let model: SettingsModel

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Text(decisionText)
        .font(PanelTypography.caption)
        .foregroundStyle(rule.decision == .allow ? CountersignPalette.accentText : Color.red)
        .frame(width: 40, alignment: .leading)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(scopeText)
          .font(PanelTypography.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(patternText)
          .font(PanelTypography.code)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
          .help(patternText)
        if rule.decision == .deny, let message = rule.message {
          Text(message)
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .truncationMode(.tail)
        }
      }
      Spacer(minLength: 8)
      HStack(spacing: 8) {
        Button {
          edit()
        } label: {
          Image(systemName: "pencil")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Edit this rule")
        .accessibilityLabel("Edit rule")
        Button {
          remove()
        } label: {
          Image(systemName: "minus.circle.fill")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove this rule")
        .accessibilityLabel("Remove rule")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color.primary.opacity(0.05))
    )
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { edit() }
  }

  private func edit() {
    RuleSheet.present(model: model, editing: rule, on: NSApp.keyWindow)
  }

  private func remove() {
    let removedRule = rule
    RemoveRulePrompt.present(
      lines: ["\(decisionText): \(patternText)", scopeText], on: NSApp.keyWindow
    ) { [model] in
      model.removeRule(removedRule)
    }
  }

  private var decisionText: String {
    rule.decision == .allow ? "Allow" : "Deny"
  }

  private var scopeText: String {
    let agent = rule.agent?.displayName ?? "Any agent"
    return "\(agent) · \(model.projectText(for: rule))"
  }

  private var patternText: String {
    if let command = rule.command { return command }
    if let tool = rule.tool { return "tool \(tool)" }
    return "Any request"
  }
}

private struct UnreadableRulesNotice: View {
  let model: SettingsModel

  var body: some View {
    let count = model.unreadableRuleCount
    if count > 0 {
      VStack(alignment: .leading, spacing: 8) {
        InlineMessage(
          "\(count) \(count == 1 ? "rule" : "rules") in config.json couldn't be read."
            + " countersign doctor lists them.",
          tone: .warning)
        HStack(spacing: 8) {
          Button("Open in Editor") { model.openConfigInEditor(from: .rules) }
            .buttonStyle(SecondaryButtonStyle())
          Spacer(minLength: 0)
        }
        if let error = model.editorOpenProblem(at: .rules) {
          InlineMessage(error, tone: .problem)
        }
      }
    }
  }
}
