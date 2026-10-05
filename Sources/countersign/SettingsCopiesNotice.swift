import AppKit
import ApprovalCore
import SwiftUI

struct DuplicateInstallNotice: View {
  static let contentInset: CGFloat = 18
  static let promptButton = "Copy a Prompt for Your Agent"
  static let promptCaption = "Paste it into Claude Code, Codex or any agent to talk it through."

  let duplicateInstall: DuplicateInstall
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      InlineMessage(duplicateInstall.title, tone: .warning)
      VStack(alignment: .leading, spacing: 10) {
        ChangesDisclosure(isExpanded: model.showsCopies, subject: "copies") {
          model.toggleCopies()
        }
        if model.showsCopies {
          Text(DuplicateInstall.explanation)
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Text(DuplicateInstall.question)
            .font(.system(size: 13, weight: .semibold))
          ForEach(Array(duplicateInstall.entries.enumerated()), id: \.offset) { index, entry in
            InstalledCopyRow(entry: entry, isSelected: model.selectedCopyIndex == index) {
              model.selectCopy(index)
            }
          }
          if let selected = model.selectedCopyIndex,
            duplicateInstall.entries.indices.contains(selected)
          {
            steps(keeping: duplicateInstall.entries[selected])
          }
          agentPrompt
        }
      }
      .padding(.leading, Self.contentInset)
    }
    .padding(.bottom, 4)
  }

  private func steps(keeping entry: DuplicateInstallEntry) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("To keep \(entry.label):")
        .font(.system(size: 13, weight: .semibold))
      ForEach(Array(model.selectedCopySteps.enumerated()), id: \.offset) { index, step in
        CommandStep(
          text: step.text, command: step.command, isCopied: model.copied == .copyStep(index)
        ) {
          model.copy(.copyStep(index))
        }
      }
    }
    .padding(.top, 4)
  }

  private var agentPrompt: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button(model.copied == .agentPrompt ? "Copied" : Self.promptButton) {
        model.copy(.agentPrompt)
      }
      .buttonStyle(SecondaryButtonStyle())
      Text(Self.promptCaption)
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 4)
  }
}

struct InstallVersionMismatchNotice: View {
  let mismatch: InstallVersionMismatch
  let model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      InlineMessage(mismatch.title, tone: .warning)
      CommandStep(
        text: mismatch.advice, command: mismatch.command,
        isCopied: model.copied == .versionCommand
      ) {
        model.copy(.versionCommand)
      }
      .padding(.leading, DuplicateInstallNotice.contentInset)
    }
    .padding(.bottom, 4)
  }
}

private struct CommandStep: View {
  let text: String
  let command: String?
  let isCopied: Bool
  let copy: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        Text(text)
          .font(PanelTypography.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        if command != nil {
          Button(isCopied ? "Copied" : "Copy", action: copy)
            .buttonStyle(SecondaryButtonStyle())
        }
      }
      if let command {
        CodeCard {
          Text(command)
            .font(PanelTypography.code)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }
}

private struct InstalledCopyRow: View {
  let entry: DuplicateInstallEntry
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 13))
          .foregroundStyle(isSelected ? CountersignPalette.accent : Color.secondary)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            Text(entry.label)
              .font(.system(size: 13, weight: .semibold))
            if entry.isCalledByHooks {
              Chip("Hooks call this one", tint: Color(nsColor: .systemGreen))
            }
            if entry.isRunning {
              Chip("Running now")
            }
            if entry.isNewest {
              Chip("Newest")
            }
            if entry.hasApp {
              Chip("Menu-bar app")
            }
          }
          Text(entry.paths.joined(separator: "\n"))
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
