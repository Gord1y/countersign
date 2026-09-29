import ApprovalCore
import SwiftUI

private struct QuestionContentWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat { 0 }
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

struct QuestionCardBackground: ViewModifier {
  let selected: Bool
  let isHovering: Bool

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            selected
              ? CountersignPalette.accentText.opacity(0.10)
              : Color.primary.opacity(isHovering ? 0.07 : 0.04))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(CountersignPalette.accentText, lineWidth: selected ? 1.5 : 0)
      )
  }
}

struct OptionCard<Content: View>: View {
  let selected: Bool
  let action: () -> Void
  let content: Content

  @State private var isHovering = false

  init(
    selected: Bool, action: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.selected = selected
    self.action = action
    self.content = content()
  }

  var body: some View {
    Button(action: action) {
      content
        .modifier(QuestionCardBackground(selected: selected, isHovering: isHovering))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering in isHovering = hovering }
  }
}

private enum QuestionField: Hashable {
  case other(Int)
  case notes(Int)
}

private struct OtherCard: View {
  let selected: Bool
  let multiSelect: Bool
  @Binding var text: String
  let focus: FocusState<QuestionField?>.Binding
  let field: QuestionField
  let onFocusChange: (Bool) -> Void

  @State private var isHovering = false

  private var placeholder: String {
    multiSelect
      ? "Type an answer to add to your picks"
      : "Type an answer instead of picking one"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Your own answer")
        .font(PanelTypography.secondary)
        .foregroundStyle(.secondary)
      TextField(placeholder, text: $text, axis: .vertical)
        .lineLimit(1...4)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .focused(focus, equals: field)
    }
    .modifier(QuestionCardBackground(selected: selected, isHovering: isHovering))
    .onHover { hovering in isHovering = hovering }
    .onChange(of: focus.wrappedValue == field) { _, isFocused in
      onFocusChange(isFocused)
    }
  }
}

struct QuestionView: View {
  let model: PanelModel
  let questions: [Question]
  let availableHeight: CGFloat

  @State private var answers: [QuestionAnswer]
  @State private var selectedIndex = 0
  @State private var lastClickedOptionIndex: [Int: Int] = [:]
  @State private var notesExpanded: [Int: Bool] = [:]
  @State private var contentWidth: CGFloat = 0
  @FocusState private var focusedField: QuestionField?

  init(model: PanelModel, questions: [Question], availableHeight: CGFloat) {
    self.model = model
    self.questions = questions
    self.availableHeight = availableHeight
    _answers = State(initialValue: questions.map { _ in QuestionAnswer() })
  }

  private var allAnswered: Bool {
    zip(questions, answers).allSatisfy { QuestionResponse.isAnswered($1, for: $0) }
  }

  private var nextUnansweredIndex: Int? {
    guard QuestionResponse.isAnswered(answers[selectedIndex], for: questions[selectedIndex]) else {
      return nil
    }
    return unansweredIndex(after: selectedIndex)
  }

  private func unansweredIndex(after index: Int) -> Int? {
    let ordered = Array(index + 1..<questions.count) + Array(0..<index)
    return ordered.first { !QuestionResponse.isAnswered(answers[$0], for: questions[$0]) }
  }

  var body: some View {
    PanelScaffold(model: model, availableHeight: availableHeight) {
      VStack(alignment: .leading, spacing: 12) {
        tabRow
        ZStack(alignment: .topLeading) {
          ForEach(questions.indices, id: \.self) { index in
            questionBody(index: index)
              .opacity(index == selectedIndex ? 1 : 0)
              .allowsHitTesting(index == selectedIndex)
              .accessibilityHidden(index != selectedIndex)
          }
        }
      }
      .reportWidth(to: QuestionContentWidthPreferenceKey.self)
      .onPreferenceChange(QuestionContentWidthPreferenceKey.self) { contentWidth = $0 }
    } footer: {
      actions
    }
    .onAppear { model.keyHandler = PanelKeyHandler(uses: usesKey, perform: handleKey) }
    .onChange(of: selectedIndex) {
      focusedField = nil
    }
  }

  private var tabRow: some View {
    HStack(spacing: 8) {
      ForEach(questions.indices, id: \.self) { index in
        tabChip(index: index)
      }
    }
  }

  private func tabLabel(_ index: Int) -> String {
    "\(index + 1)  \(questions[index].header ?? "Q\(index + 1)")"
  }

  private func tabChip(index: Int) -> some View {
    let answered = QuestionResponse.isAnswered(answers[index], for: questions[index])
    let selected = index == selectedIndex
    return Button {
      selectedIndex = index
    } label: {
      HStack(spacing: 4) {
        Text(tabLabel(index))
        if answered {
          Image(systemName: "checkmark")
        }
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(selected ? CountersignPalette.accentText : Color.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule()
          .fill(
            selected ? CountersignPalette.accentText.opacity(0.18) : Color.primary.opacity(0.06))
      )
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func questionBody(index: Int) -> some View {
    let question = questions[index]
    let hasPreview = question.options.contains { $0.preview != nil }
    VStack(alignment: .leading, spacing: 12) {
      Text(question.question)
        .font(PanelTypography.title)
        .fixedSize(horizontal: false, vertical: true)
      if hasPreview {
        HStack(alignment: .top, spacing: 12) {
          optionList(index: index, question: question)
            .frame(maxWidth: .infinity, alignment: .leading)
          previewPane(index: index, question: question)
            .frame(width: contentWidth > 0 ? contentWidth * 0.45 : nil, alignment: .leading)
        }
      } else {
        optionList(index: index, question: question)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func optionList(index: Int, question: Question) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
        optionRow(
          index: index, optionIndex: optionIndex, option: option,
          multiSelect: question.multiSelect)
      }
      otherRow(index: index, question: question)
      notesSection(index: index)
    }
  }

  private func optionRow(
    index: Int, optionIndex: Int, option: QuestionOption, multiSelect: Bool
  ) -> some View {
    let selected = answers[index].selectedOptions.contains(optionIndex)
    return OptionCard(
      selected: selected,
      action: { pickOption(questionIndex: index, optionIndex: optionIndex) },
      content: {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          KeyHint("\(optionIndex + 1)")
          Text(Image(systemName: indicatorSymbol(selected: selected, multiSelect: multiSelect)))
            .font(.system(size: 13))
            .foregroundStyle(selected ? CountersignPalette.accentText : Color.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(option.label)
              .font(.system(size: 13, weight: .medium))
              .fixedSize(horizontal: false, vertical: true)
            if let description = option.description {
              Text(description)
                .font(PanelTypography.secondary)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    )
  }

  private func otherRow(index: Int, question: Question) -> some View {
    OtherCard(
      selected: answers[index].otherSelected, multiSelect: question.multiSelect,
      text: otherTextBinding(index: index, question: question),
      focus: $focusedField, field: .other(index),
      onFocusChange: { isFocused in
        if isFocused {
          markOtherFocused(index: index, question: question)
        } else {
          clearOtherIfBlank(index: index)
        }
      }
    )
    .disabled(index != selectedIndex)
  }

  private func markOtherFocused(index: Int, question: Question) {
    answers[index].otherSelected = true
    if !question.multiSelect {
      answers[index].selectedOptions = []
    }
  }

  private func clearOtherIfBlank(index: Int) {
    guard answers[index].otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    answers[index].otherSelected = false
  }

  @ViewBuilder
  private func notesSection(index: Int) -> some View {
    if model.questionNotes {
      if (notesExpanded[index] ?? false) || !answers[index].notes.isEmpty {
        TextField("Note for Claude (optional)", text: notesBinding(index: index), axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...4)
          .focused($focusedField, equals: .notes(index))
          .disabled(index != selectedIndex)
      } else {
        Button("+ Add a note") {
          notesExpanded[index] = true
        }
        .buttonStyle(LinkButtonStyle())
      }
    }
  }

  private func indicatorSymbol(selected: Bool, multiSelect: Bool) -> String {
    if multiSelect {
      return selected ? "checkmark.square.fill" : "square"
    }
    return selected ? "largecircle.fill.circle" : "circle"
  }

  private func previewText(index: Int, question: Question) -> String? {
    if question.multiSelect {
      guard let lastIndex = lastClickedOptionIndex[index],
        question.options.indices.contains(lastIndex)
      else { return nil }
      return question.options[lastIndex].preview
    }
    guard let selectedIndex = answers[index].selectedOptions.first,
      question.options.indices.contains(selectedIndex)
    else { return nil }
    return question.options[selectedIndex].preview
  }

  private func previewPane(index: Int, question: Question) -> some View {
    CodeCard {
      Group {
        if let preview = previewText(index: index, question: question) {
          Text(preview)
            .font(.system(size: 11.5, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("No preview")
            .font(PanelTypography.secondary)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func pickOption(questionIndex: Int, optionIndex: Int) {
    let question = questions[questionIndex]
    lastClickedOptionIndex[questionIndex] = optionIndex
    if question.multiSelect {
      if answers[questionIndex].selectedOptions.contains(optionIndex) {
        answers[questionIndex].selectedOptions.remove(optionIndex)
      } else {
        answers[questionIndex].selectedOptions.insert(optionIndex)
      }
    } else {
      answers[questionIndex].selectedOptions = [optionIndex]
      answers[questionIndex].otherSelected = false
      advanceToNextUnanswered(after: questionIndex)
    }
  }

  private func advanceToNextUnanswered(after index: Int) {
    guard
      let next = (index + 1..<questions.count).first(where: {
        !QuestionResponse.isAnswered(answers[$0], for: questions[$0])
      })
    else { return }
    selectedIndex = next
  }

  private func otherTextBinding(index: Int, question: Question) -> Binding<String> {
    Binding(
      get: { answers[index].otherText },
      set: { newValue in
        answers[index].otherText = newValue
        guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        answers[index].otherSelected = true
        if !question.multiSelect {
          answers[index].selectedOptions = []
        }
      }
    )
  }

  private func notesBinding(index: Int) -> Binding<String> {
    Binding(
      get: { answers[index].notes },
      set: { answers[index].notes = $0 }
    )
  }

  private var actions: some View {
    HStack {
      AnswerInChatButton(model: model)

      Spacer()

      if let nextIndex = nextUnansweredIndex {
        Button("Next") {
          selectedIndex = nextIndex
        }
        .buttonStyle(SecondaryButtonStyle())
      }

      Button {
        submit()
      } label: {
        HStack(alignment: .keyHintMidline, spacing: 4) {
          Text("Submit")
            .keyHintTextGuide(capHeight: PrimaryButtonStyle.labelCapHeight)
          KeyHint("⏎", placement: .onAccent)
            .keyHintGuide()
        }
      }
      .buttonStyle(PrimaryButtonStyle())
      .disabled(!model.isArmed || !allAnswered)
    }
  }

  private func submit() {
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: model.request.toolInput,
      includeNotes: model.questionNotes)
    model.finish(outcome)
  }

  private func usesKey(_ key: PanelKey) -> Bool {
    switch key {
    case .primary, .left, .right:
      return true
    case .alternate, .secondary, .up, .down:
      return false
    case .digit(let digit):
      return questions.indices.contains(selectedIndex)
        && questions[selectedIndex].options.indices.contains(digit - 1)
    }
  }

  private func handleKey(_ key: PanelKey) {
    guard model.isArmed, usesKey(key) else { return }
    switch key {
    case .primary:
      if allAnswered {
        submit()
      } else if let next = unansweredIndex(after: selectedIndex) {
        selectedIndex = next
      }
    case .alternate, .secondary, .up, .down:
      break
    case .digit(let digit):
      pickOption(questionIndex: selectedIndex, optionIndex: digit - 1)
    case .left:
      guard selectedIndex > 0 else { return }
      selectedIndex -= 1
    case .right:
      guard selectedIndex < questions.count - 1 else { return }
      selectedIndex += 1
    }
  }
}
