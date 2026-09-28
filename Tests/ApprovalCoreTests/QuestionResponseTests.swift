import Foundation
import Testing

@testable import ApprovalCore

@Suite struct QuestionResponseTests {
  private func loadQuestions() throws -> (questions: [Question], toolInput: JSONValue) {
    let request = try ClaudeAdapter.parse(FixtureLoader.data("claude-questions"))
    guard case .questions(let questions) = request.kind else {
      Issue.record("expected questions")
      return ([], .null)
    }
    return (questions, request.toolInput)
  }

  @Test func singleSelectWithPreviewAnnotation() throws {
    let (questions, toolInput) = try loadQuestions()
    let answers = [
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [0, 2]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, let updatedPermissions) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedPermissions.isEmpty)
    #expect(updatedInput?["answers"]?[questions[0].question]?.stringValue == "Redis")
    #expect(
      updatedInput?["annotations"]?[questions[0].question]?["preview"]?.stringValue
        == questions[0].options[0].preview)
  }

  @Test func multiSelectOrderJoinsWithComma() throws {
    let (questions, toolInput) = try loadQuestions()
    let answers = [
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [3, 0]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedInput?["answers"]?[questions[1].question]?.stringValue == "staging, canary")
  }

  @Test func multiSelectWithOther() throws {
    let (questions, toolInput) = try loadQuestions()
    var targets = QuestionAnswer(selectedOptions: [0])
    targets.otherSelected = true
    targets.otherText = "  custom-region  "
    let answers = [
      QuestionAnswer(selectedOptions: [0]),
      targets,
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(
      updatedInput?["answers"]?[questions[1].question]?.stringValue
        == "staging, custom-region")
  }

  @Test func singleSelectOther() throws {
    let (questions, toolInput) = try loadQuestions()
    var storage = QuestionAnswer()
    storage.otherSelected = true
    storage.otherText = " Memcached "
    let answers = [
      storage,
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedInput?["answers"]?[questions[0].question]?.stringValue == "Memcached")
    #expect(updatedInput?["annotations"]?[questions[0].question] == nil)
  }

  @Test func notesAreTrimmed() throws {
    let (questions, toolInput) = try loadQuestions()
    var storage = QuestionAnswer(selectedOptions: [1])
    storage.notes = "  keep it simple  "
    let answers = [
      storage,
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(
      updatedInput?["annotations"]?[questions[0].question]?["notes"]?.stringValue
        == "keep it simple")
  }

  @Test func emptyAnnotationIsOmitted() throws {
    let (questions, toolInput) = try loadQuestions()
    let answers = [
      QuestionAnswer(selectedOptions: [2]),
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedInput?["annotations"]?[questions[0].question] == nil)
  }

  @Test func annotationsKeyOmittedWhenNoNotesOrPreviews() throws {
    let (questions, toolInput) = try loadQuestions()
    let answers = [
      QuestionAnswer(selectedOptions: [2]),
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedInput?["annotations"] == nil)
  }

  @Test func questionsAreEchoedUnchanged() throws {
    let (questions, toolInput) = try loadQuestions()
    let answers = [
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedInput?["questions"] == toolInput["questions"])
  }

  @Test func unansweredQuestionYieldsNoDecision() throws {
    let (questions, toolInput) = try loadQuestions()
    let answers = [
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    #expect(outcome == .noDecision)
  }

  @Test func notesOffStillSendsThePreviewAnnotation() throws {
    let (questions, toolInput) = try loadQuestions()
    var storage = QuestionAnswer(selectedOptions: [0])
    storage.notes = "keep it simple"
    let answers = [
      storage,
      QuestionAnswer(selectedOptions: [0, 2]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput, includeNotes: false)
    guard case .allow(let updatedInput, let updatedPermissions) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedPermissions.isEmpty)
    #expect(updatedInput?["answers"]?[questions[0].question]?.stringValue == "Redis")
    #expect(
      updatedInput?["annotations"]?[questions[0].question]?["preview"]?.stringValue
        == questions[0].options[0].preview)
    #expect(updatedInput?["annotations"]?[questions[0].question]?["notes"] == nil)
  }

  @Test func notesOffWithNoPreviewOmitsAnnotations() throws {
    let (questions, toolInput) = try loadQuestions()
    var storage = QuestionAnswer(selectedOptions: [2])
    storage.notes = "keep it simple"
    let answers = [
      storage,
      QuestionAnswer(selectedOptions: [0]),
      QuestionAnswer(selectedOptions: [1]),
    ]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput, includeNotes: false)
    guard case .allow(let updatedInput, _) = outcome else {
      Issue.record("expected allow")
      return
    }
    #expect(updatedInput?["annotations"] == nil)
  }

  @Test func mismatchedCountsYieldNoDecision() throws {
    let (questions, toolInput) = try loadQuestions()
    let answers = [QuestionAnswer(selectedOptions: [0])]
    let outcome = QuestionResponse.outcome(
      questions: questions, answers: answers, toolInput: toolInput)
    #expect(outcome == .noDecision)
  }
}
