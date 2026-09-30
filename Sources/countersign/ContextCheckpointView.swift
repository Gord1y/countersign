import ApprovalCore
import SwiftUI

struct ContextCheckpointView: View {
  let model: PanelModel
  let prompt: ContextCheckpointPrompt
  let availableHeight: CGFloat

  @State private var highlighted: ContextCheckpointChoice

  init(model: PanelModel, prompt: ContextCheckpointPrompt, availableHeight: CGFloat) {
    self.model = model
    self.prompt = prompt
    self.availableHeight = availableHeight
    _highlighted = State(initialValue: ContextCheckpointChoice.highlighted(for: prompt.level))
  }

  private static let choices = ContextCheckpointChoice.allCases

  var body: some View {
    PanelScaffold(model: model, availableHeight: availableHeight) {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Context ~\(ContextCheckpointNotes.tokenText(prompt.tokens)) tokens")
            .font(PanelTypography.title)
          ladder
          Text(levelLine)
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if model.sessionIdle {
            Text("Claude is idle: this reaches it with your next message.")
              .font(PanelTypography.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(Self.choices.enumerated()), id: \.offset) { index, choice in
            choiceCard(index: index, choice: choice)
          }
        }
      }
    } footer: {
      HStack {
        Spacer()
        Button {
          perform(highlighted)
        } label: {
          HStack(alignment: .keyHintMidline, spacing: 4) {
            Text(highlighted.title)
              .keyHintTextGuide(capHeight: PrimaryButtonStyle.labelCapHeight)
            KeyHint("⏎", placement: .onAccent)
              .keyHintGuide()
          }
        }
        .buttonStyle(PrimaryButtonStyle())
        .panelPrimaryAccessibility(shortcut: "⏎", model: model)
        .disabled(!model.isArmed)
      }
    }
    .onAppear { model.keyHandler = PanelKeyHandler(uses: usesKey, perform: handleKey) }
  }

  private var ladder: some View {
    HStack(spacing: 6) {
      ForEach(Array(ContextLevel.allCases.enumerated()), id: \.offset) { index, level in
        if index > 0 {
          Text("·")
            .foregroundStyle(.secondary)
        }
        Text("\(Self.levelName(level)) \(ladderText(at: index))")
          .foregroundStyle(level == prompt.level ? CountersignPalette.accentText : Color.secondary)
      }
    }
    .font(PanelTypography.caption)
  }

  private func ladderText(at index: Int) -> String {
    guard prompt.ladder.indices.contains(index) else { return "" }
    return ContextCheckpointNotes.tokenText(prompt.ladder[index])
  }

  private static func levelName(_ level: ContextLevel) -> String {
    switch level {
    case .soft: return "Soft"
    case .status: return "Status"
    case .insist: return "Insist"
    }
  }

  private var levelLine: String {
    switch prompt.level {
    case .soft: return "A good moment to compact, if a piece of work just finished."
    case .status: return "Worth a status check before the session grows further."
    case .insist: return "Past the point where long sessions keep working well."
    }
  }

  private func description(for choice: ContextCheckpointChoice) -> String {
    switch choice {
    case .continueWorking:
      return "Keep working. Nothing is sent to Claude."
    case .compactAfterStep:
      return
        "Claude finishes the current step, then lists what the summary must keep, so you can run /compact."
    case .handOff:
      return "Claude writes \(prompt.handoffFile) and stops, ready for /clear."
    case .notThisSession:
      return "No more checkpoints until this session ends."
    }
  }

  private func choiceCard(index: Int, choice: ContextCheckpointChoice) -> some View {
    OptionCard(
      selected: choice == highlighted,
      shortcut: "\(index + 1)",
      action: { perform(choice) },
      content: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          KeyHint("\(index + 1)")
          VStack(alignment: .leading, spacing: 2) {
            Text(choice.title)
              .font(.system(size: 13, weight: .medium))
              .fixedSize(horizontal: false, vertical: true)
            Text(description(for: choice))
              .font(PanelTypography.secondary)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    )
  }

  private func perform(_ choice: ContextCheckpointChoice) {
    model.chooseCheckpoint(choice, prompt: prompt)
  }

  private func usesKey(_ key: PanelKey) -> Bool {
    switch key {
    case .primary, .up, .down:
      return true
    case .alternate, .secondary, .left, .right:
      return false
    case .digit(let digit):
      return Self.choices.indices.contains(digit - 1)
    }
  }

  private func handleKey(_ key: PanelKey) {
    guard model.isArmed, usesKey(key) else { return }
    switch key {
    case .primary:
      perform(highlighted)
    case .up:
      moveHighlight(by: -1)
    case .down:
      moveHighlight(by: 1)
    case .digit(let digit):
      highlighted = Self.choices[digit - 1]
    case .alternate, .secondary, .left, .right:
      break
    }
  }

  private func moveHighlight(by step: Int) {
    guard let current = Self.choices.firstIndex(of: highlighted) else { return }
    let next = current + step
    guard Self.choices.indices.contains(next) else { return }
    highlighted = Self.choices[next]
  }
}
