import AppKit
import ApprovalCore
import SwiftUI

struct HelpSection: View {
  let model: SettingsModel

  var body: some View {
    SettingsSection(.help) {
      SettingsGroup {
        PreferenceRow(
          "Tour", caption: "The short introduction shown the first time Settings opened."
        ) {
          Button("Show the Tour") { model.requestTour?() }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
        }
        SettingsDivider()
        PreferenceRow(
          "Documentation",
          caption: "Setup, every setting, troubleshooting and what each agent supports."
        ) {
          if let url = CompanionMenu.documentationURL {
            Button("Open") { openInDefaultApp(url) }
              .buttonStyle(SecondaryButtonStyle())
              .fixedSize()
          }
        }
        SettingsDivider()
        PreferenceRow(
          "Ask a question", caption: "GitHub Discussions, for how-to questions and ideas."
        ) {
          if let url = CompanionMenu.askAQuestionURL {
            Button("Ask…") { openInDefaultApp(url) }
              .buttonStyle(SecondaryButtonStyle())
              .fixedSize()
          }
        }
        SettingsDivider()
        PreferenceRow(
          "Report a problem",
          caption:
            "Opens a GitHub issue with your macOS version and countersign doctor's report"
            + " filled in."
        ) {
          Button("Report…") {
            if let url = ReportProblem.url() { openInDefaultApp(url) }
          }
          .buttonStyle(SecondaryButtonStyle())
          .fixedSize()
        }
        SettingsDivider()
        PreferenceRow(
          "Contact the developer", caption: "For anything that isn't a bug or a question."
        ) {
          if let url = CompanionMenu.contactDeveloperURL {
            Button("Contact…") { openInDefaultApp(url) }
              .buttonStyle(SecondaryButtonStyle())
              .fixedSize()
          }
        }
      }
      SettingsGroup {
        UpdatesRow(model: model)
      }
      SettingsGroup {
        PreferenceRow(
          "Support Countersign",
          caption:
            "Countersign is free and open source. If it saves you time, you can support its"
            + " development."
        ) {
          HStack(spacing: 8) {
            if let url = CompanionMenu.sponsorURL {
              Button("Sponsor on GitHub") { openInDefaultApp(url) }
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
            }
            if let url = CompanionMenu.buyMeACoffeeURL {
              Button("Buy Me a Coffee") { openInDefaultApp(url) }
                .buttonStyle(SecondaryButtonStyle())
                .fixedSize()
            }
          }
        }
      }
    }
  }
}

private struct UpdatesRow: View {
  static let title = "Updates"

  let model: SettingsModel

  var body: some View {
    PreferenceRow(Self.title, caption: caption) {
      EmptyView()
    } detail: {
      HStack(spacing: 8) {
        if case .newerAvailable(let availability) = model.updateCheckPhase {
          if let releaseNotesURL = availability.releaseNotesURL {
            Button("Release Notes") { openInDefaultApp(releaseNotesURL) }
              .buttonStyle(SecondaryButtonStyle())
          }
          Button(model.copied == .upgradeCommand ? "Copied" : "Copy Upgrade Command") {
            model.copy(.upgradeCommand)
          }
          .buttonStyle(SecondaryButtonStyle())
        }
        Button("Check for Updates") { Task { await model.checkForUpdates() } }
          .buttonStyle(SecondaryButtonStyle())
          .disabled(model.updateCheckPhase == .checking)
      }
    }
  }

  private var caption: String {
    switch model.updateCheckPhase {
    case .idle: return "Check whether a newer Countersign is out."
    case .checking: return "Checking…"
    case .upToDate: return "Countersign is up to date."
    case .newerAvailable(let availability):
      return "Countersign \(availability.version) is available."
    case .failed: return "Couldn't check for updates. Try again later."
    }
  }
}

private func openInDefaultApp(_ url: URL) {
  NSWorkspace.shared.open(url)
}
