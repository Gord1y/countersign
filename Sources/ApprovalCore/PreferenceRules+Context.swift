import Foundation

public enum ContextTextError: Error, Sendable, Equatable, CustomStringConvertible {
  case ladder
  case emptyPrefix
  case prefixContainsWhitespace
  case emptyHandoffFile
  case emptyNote
  case noteTooLong

  public var description: String {
    switch self {
    case .ladder:
      return "Enter three ascending numbers of thousands of tokens"
    case .emptyPrefix:
      return "Enter a model ID prefix, like claude-opus-5"
    case .prefixContainsWhitespace:
      return "A model ID prefix has no spaces"
    case .emptyHandoffFile:
      return "Enter a file path"
    case .emptyNote:
      return "Enter the note"
    case .noteTooLong:
      return "A note is at most \(ContextCheckpointNotes.maximumLength) characters"
    }
  }
}

extension PreferenceRules {
  public static let contextLadderThousands: ClosedRange<Int> = 1...2000
  public static let contextLadderLength = 3
  public static let contextRearmPercentRange: ClosedRange<Double> = 10...95
  public static let contextRearmPercentStep: Double = 5

  public static func contextLadder(fromThousands text: String) -> Result<[Int], ContextTextError> {
    let words = text.split { $0 == "," || $0.isWhitespace }.map(String.init)
    guard words.count == contextLadderLength else { return .failure(.ladder) }
    var thousands: [Int] = []
    for word in words {
      guard let value = Int(word), contextLadderThousands.contains(value) else {
        return .failure(.ladder)
      }
      if let previous = thousands.last, value <= previous { return .failure(.ladder) }
      thousands.append(value)
    }
    return .success(thousands.map { $0 * 1000 })
  }

  public static func contextLadderText(_ tokens: [Int]) -> String {
    tokens.map { String(($0 + 500) / 1000) }.joined(separator: ", ")
  }

  public static func contextModelPrefix(_ text: String) -> Result<String, ContextTextError> {
    let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prefix.isEmpty else { return .failure(.emptyPrefix) }
    guard !prefix.contains(where: \.isWhitespace) else {
      return .failure(.prefixContainsWhitespace)
    }
    return .success(prefix)
  }

  public static func contextHandoffFile(_ text: String) -> Result<String, ContextTextError> {
    let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return .failure(.emptyHandoffFile) }
    return .success(path)
  }

  public static func contextNote(_ text: String) -> Result<String, ContextTextError> {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.emptyNote)
    }
    guard text.count <= ContextCheckpointNotes.maximumLength else {
      return .failure(.noteTooLong)
    }
    return .success(text)
  }

  public static func contextRearmBelow(percent: Double) -> Double {
    let clamped = min(
      max(percent, contextRearmPercentRange.lowerBound), contextRearmPercentRange.upperBound)
    return ((clamped / contextRearmPercentStep).rounded() * contextRearmPercentStep) / 100
  }

  public static func contextRearmPercent(_ ratio: Double) -> Double {
    (ratio * 100 / contextRearmPercentStep).rounded() * contextRearmPercentStep
  }
}
