import AppKit
import ApprovalCore
import SwiftUI

@MainActor
enum ContextNotesSheet {
  static func present(model: SettingsModel, on window: NSWindow?) {
    guard let window else { return }
    let sheetWindow = NSWindow(
      contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    sheetWindow.isReleasedWhenClosed = false
    let hostingController = NSHostingController(
      rootView: ContextNotesSheetView(
        model: model,
        close: { [weak window, weak sheetWindow] in
          guard let window, let sheetWindow else { return }
          window.endSheet(sheetWindow)
          sheetWindow.contentViewController = nil
        }))
    sheetWindow.contentViewController = hostingController
    window.beginSheet(sheetWindow)
  }

  static func defaultText(for name: PreferenceName) -> String {
    let notes = ContextCheckpointNotes.default
    switch name {
    case .contextNoteSoft: return notes.soft
    case .contextNoteStatus: return notes.status
    case .contextNoteInsist: return notes.insist
    case .contextNoteCompact: return notes.compact
    case .contextNoteHandoff: return notes.handoff
    default: return ""
    }
  }
}

struct ContextNotesSheetView: View {
  static let title = "Context notes"
  static let placeholders =
    "Use {tokens} for the context size and {handoffFile} for the handoff file."
  static let restoreTitle = "Restore Default"
  static let width: CGFloat = 560
  static let height: CGFloat = 620
  static let editorHeight: CGFloat = 92

  let model: SettingsModel
  let close: () -> Void

  @State private var drafts: [PreferenceName: String]

  init(model: SettingsModel, close: @escaping () -> Void) {
    self.model = model
    self.close = close
    _drafts = State(
      initialValue: Dictionary(
        uniqueKeysWithValues: SettingsModel.contextNoteNames.map {
          ($0, model.contextText(for: $0))
        }
      ))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 4) {
        Text(Self.title)
          .font(PanelTypography.title)
        Text(Self.placeholders)
          .font(PanelTypography.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 12)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(SettingsModel.contextNoteNames, id: \.self) { name in
            noteEditor(name)
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
      }
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button("Cancel") { cancel() }
          .buttonStyle(SecondaryButtonStyle())
          .keyboardShortcut(.cancelAction)
        Button("Save") { save() }
          .buttonStyle(PrimaryButtonStyle())
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(width: Self.width, height: Self.height, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private func text(_ name: PreferenceName) -> String {
    drafts[name] ?? ""
  }

  private func problem(_ name: PreferenceName) -> String? {
    if case .failure(let error) = PreferenceRules.contextNote(text(name)) {
      return error.description
    }
    return model.contextProblem(name)
  }

  private func noteEditor(_ name: PreferenceName) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(name.title)
            .font(PanelTypography.body)
          Text(name.caption)
            .font(PanelTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        Button(Self.restoreTitle) {
          drafts[name] = ContextNotesSheet.defaultText(for: name)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(text(name) == ContextNotesSheet.defaultText(for: name))
      }
      TextEditor(
        text: Binding(get: { text(name) }, set: { drafts[name] = $0 })
      )
      .font(PanelTypography.body)
      .scrollContentBackground(.hidden)
      .padding(6)
      .frame(height: Self.editorHeight)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.primary.opacity(0.05))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(Color.primary.opacity(0.12), lineWidth: 1)
      )
      if let problem = problem(name) {
        InlineMessage(problem, tone: .problem)
      }
    }
  }

  private func cancel() {
    model.clearContextNoteErrors()
    close()
  }

  private func save() {
    if model.saveContextNotes(drafts) {
      close()
    }
  }
}
