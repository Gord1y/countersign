import AppKit
import ApprovalCore
import SwiftUI

enum SkillsText {
  static let notInstalled =
    "countersign-skills isn't installed. It adds skills and rules for Claude Code, Codex and"
    + " Antigravity."
  static let openRepositoryTitle = "Open countersign-skills on GitHub"
  static let repositoryAddress = "https://github.com/Gord1y/countersign-skills"

  static func agentName(_ agent: String) -> String {
    switch agent {
    case "claude": return "Claude Code"
    case "codex": return "Codex"
    case "antigravity": return "Antigravity"
    default: return agent
    }
  }

  static func updatesTitle(count: Int) -> String {
    count == 1 ? "Update for 1 skill" : "Updates for \(count) skills"
  }
}

struct SkillsSection: View {
  let model: SettingsModel

  var body: some View {
    SettingsSection(.skills) {
      SkillsContent(model: model)
    }
  }
}

private struct SkillsContent: View {
  let model: SettingsModel

  var body: some View {
    let overview = model.skillsOverview
    switch overview.availability {
    case .notInstalled:
      VStack(alignment: .leading, spacing: 10) {
        Text(SkillsText.notInstalled)
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button(SkillsText.openRepositoryTitle) { openRepository() }
          .buttonStyle(SecondaryButtonStyle())
      }
      .padding(SettingsMetrics.rowPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(SkillsSurface())
    case .catalogUnreadable(let folder, let reason):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 11))
          .foregroundStyle(Color(nsColor: .systemOrange))
          .accessibilityHidden(true)
        Text("Couldn't read \(shown(folder))/catalog.json: \(reason)")
          .font(PanelTypography.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      .accessibilityElement(children: .combine)
      .padding(SettingsMetrics.rowPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .modifier(SkillsSurface())
    case .ready(let setupFolder):
      ready(overview, setupFolder: setupFolder)
    }
  }

  private func openRepository() {
    guard let address = URL(string: SkillsText.repositoryAddress) else { return }
    NSWorkspace.shared.open(address)
  }

  private func shown(_ folder: URL) -> String {
    HomePath.abbreviating(folder.path, relativeTo: model.homeDirectory)
  }

  private func skillsWithUpdates(_ overview: SkillsOverview) -> Int {
    overview.skills.filter { skill in
      skill.agents.contains {
        if case .updateAvailable = $0.status { return true }
        return false
      }
    }.count
  }

  @ViewBuilder
  private func ready(_ overview: SkillsOverview, setupFolder: URL) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("From \(shown(setupFolder))")
        ForEach(overview.additions, id: \.path) { addition in
          Text("Also from \(shown(addition))")
        }
      }
      .font(PanelTypography.secondary)
      .foregroundStyle(.secondary)
      .padding(.horizontal, SettingsMetrics.rowPadding)
      .padding(.top, SettingsMetrics.rowPadding)
      if let command = overview.updateCommand {
        VStack(alignment: .leading, spacing: 8) {
          InlineMessage(
            SkillsText.updatesTitle(count: skillsWithUpdates(overview)), tone: .warning)
          HStack(alignment: .center, spacing: 8) {
            Text("Run this to update them:")
              .font(PanelTypography.secondary)
            Spacer(minLength: 8)
            Button(model.copied == .skillsUpdateCommand ? "Copied" : "Copy") {
              model.copy(.skillsUpdateCommand)
            }
            .buttonStyle(SecondaryButtonStyle())
          }
          CodeCard {
            Text(HomePath.abbreviating(command, relativeTo: model.homeDirectory))
              .font(PanelTypography.code)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.horizontal, SettingsMetrics.rowPadding)
      }
      VStack(alignment: .leading, spacing: 0) {
        ForEach(overview.skills) { skill in
          SettingsDivider()
          SkillRow(skill: skill)
        }
        if !overview.rules.isEmpty {
          SettingsDivider()
          VStack(alignment: .leading, spacing: 2) {
            Text("Rules")
              .font(.system(size: 13, weight: .semibold))
            Text(
              "\(overview.rules.count) rules: "
                + overview.rules.map(\.name).joined(separator: ", ")
            )
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
          .padding(SettingsMetrics.rowPadding)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .modifier(SkillsSurface())
  }
}

private struct SkillsSurface: ViewModifier {
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
          .fill(Color.primary.opacity(0.04))
      )
      .overlay(
        RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
          .stroke(
            contrast == .increased ? Color(nsColor: .separatorColor) : Color.primary.opacity(0.08),
            lineWidth: 1)
      )
  }
}

private struct SkillRow: View {
  let skill: SkillsOverview.Skill

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(skill.name)
          .font(.system(size: 13, weight: .semibold))
        Text(skill.version)
          .font(PanelTypography.secondary)
          .foregroundStyle(.secondary)
      }
      Text(skill.description)
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      SkillChipFlow(spacing: 5) {
        ForEach(skill.agents, id: \.agent) { install in
          chip(for: install)
        }
      }
      .padding(.top, 2)
    }
    .padding(SettingsMetrics.rowPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func chip(for install: SkillsOverview.AgentInstall) -> some View {
    let name = SkillsText.agentName(install.agent)
    switch install.status {
    case .linked:
      Chip("\(name): linked")
    case .copied(let version):
      Chip("\(name): \(version)")
    case .updateAvailable(let installed, let available):
      Chip(
        "\(name): \(installed), update to \(available)", tint: Color(nsColor: .systemOrange))
    case .notInstalled:
      Chip("\(name): not installed")
    case .agentMissing:
      EmptyView()
    }
  }
}

private struct SkillChipFlow: Layout {
  var spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var origin = CGPoint.zero
    var lineHeight: CGFloat = 0
    var widest: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if size.width == 0 { continue }
      if origin.x > 0, origin.x + size.width > maxWidth {
        origin.x = 0
        origin.y += lineHeight + spacing
        lineHeight = 0
      }
      origin.x += size.width + spacing
      widest = max(widest, origin.x - spacing)
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: proposal.width ?? widest, height: origin.y + lineHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var origin = bounds.origin
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if size.width == 0 { continue }
      if origin.x > bounds.minX, origin.x + size.width > bounds.maxX {
        origin.x = bounds.minX
        origin.y += lineHeight + spacing
        lineHeight = 0
      }
      subview.place(at: origin, anchor: .topLeading, proposal: .unspecified)
      origin.x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}
