import Foundation

public struct QuestionAnswer: Sendable, Equatable {
  public var selectedOptions: Set<Int>
  public var otherSelected: Bool
  public var otherText: String
  public var notes: String

  public init(
    selectedOptions: Set<Int> = [],
    otherSelected: Bool = false,
    otherText: String = "",
    notes: String = ""
  ) {
    self.selectedOptions = selectedOptions
    self.otherSelected = otherSelected
    self.otherText = otherText
    self.notes = notes
  }
}

public enum QuestionResponse {
  public static func isAnswered(_ answer: QuestionAnswer, for question: Question) -> Bool {
    if question.multiSelect {
      return !answer.selectedOptions.isEmpty || hasOtherText(answer)
    }
    return answer.selectedOptions.count == 1 || hasOtherText(answer)
  }

  public static func answerText(_ answer: QuestionAnswer, for question: Question) -> String? {
    guard isAnswered(answer, for: question) else { return nil }
    let trimmedOther = answer.otherText.trimmingCharacters(in: .whitespacesAndNewlines)
    let otherCounts = answer.otherSelected && !trimmedOther.isEmpty

    if question.multiSelect {
      var parts = orderedLabels(answer, for: question)
      if otherCounts {
        parts.append(trimmedOther)
      }
      return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    if answer.selectedOptions.count == 1, let index = answer.selectedOptions.first,
      question.options.indices.contains(index)
    {
      return question.options[index].label
    }
    if otherCounts {
      return trimmedOther
    }
    return nil
  }

  public static func outcome(
    questions: [Question],
    answers: [QuestionAnswer],
    toolInput: JSONValue,
    includeNotes: Bool = true
  ) -> ApprovalOutcome {
    guard questions.count == answers.count else { return .noDecision }
    guard case .object(let inputObject) = toolInput else { return .noDecision }

    var answersObject: [String: JSONValue] = [:]
    var annotationsObject: [String: JSONValue] = [:]

    for (question, answer) in zip(questions, answers) {
      guard let text = answerText(answer, for: question) else { return .noDecision }
      answersObject[question.question] = .string(text)

      var annotation: [String: JSONValue] = [:]
      let trimmedNotes = answer.notes.trimmingCharacters(in: .whitespacesAndNewlines)
      if includeNotes, !trimmedNotes.isEmpty {
        annotation["notes"] = .string(trimmedNotes)
      }
      if !question.multiSelect, answer.selectedOptions.count == 1,
        let index = answer.selectedOptions.first,
        question.options.indices.contains(index),
        let preview = question.options[index].preview
      {
        annotation["preview"] = .string(preview)
      }
      if !annotation.isEmpty {
        annotationsObject[question.question] = .object(annotation)
      }
    }

    var resultObject = inputObject
    resultObject["answers"] = .object(answersObject)
    if !annotationsObject.isEmpty {
      resultObject["annotations"] = .object(annotationsObject)
    }

    return .allow(updatedInput: .object(resultObject), updatedPermissions: [])
  }

  private static func hasOtherText(_ answer: QuestionAnswer) -> Bool {
    answer.otherSelected
      && !answer.otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func orderedLabels(_ answer: QuestionAnswer, for question: Question) -> [String] {
    question.options.indices.filter { answer.selectedOptions.contains($0) }.map {
      question.options[$0].label
    }
  }
}
