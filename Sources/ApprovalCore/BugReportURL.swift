import Foundation

public enum BugReportURL {
  public static let maxLength = 8000
  public static let formURL = URL(string: "\(base)?template=bug.yml")
  private static let base = "https://github.com/Gord1y/countersign/issues/new"
  private static let cutMarker = "…"

  public static func build(
    macOSVersion: String, countersignVersion: String, doctorText: String, homeDirectory: String
  ) -> URL? {
    guard let formURLString = formURL?.absoluteString else { return nil }
    let prefix =
      formURLString
      + "&macos-version=\(percentEncode(macOSVersion))"
      + "&countersign-version=\(percentEncode(countersignVersion))"
      + "&doctor="
    let budget = maxLength - prefix.count
    let masked = maskHomeDirectory(in: doctorText, homeDirectory: homeDirectory)
    return URL(string: prefix + doctorValue(masked, budget: budget))
  }

  private static func maskHomeDirectory(in text: String, homeDirectory: String) -> String {
    guard !homeDirectory.isEmpty else { return text }
    var result = ""
    var searchStart = text.startIndex
    while let match = text.range(of: homeDirectory, range: searchStart..<text.endIndex) {
      let precededByAPathSegment =
        match.lowerBound != text.startIndex
        && isPathCharacter(text[text.index(before: match.lowerBound)])
      let followedByMorePath =
        match.upperBound != text.endIndex && isWordCharacter(text[match.upperBound])
      if precededByAPathSegment || followedByMorePath {
        result += text[searchStart..<match.upperBound]
      } else {
        result += text[searchStart..<match.lowerBound]
        result += "~"
      }
      searchStart = match.upperBound
    }
    result += text[searchStart..<text.endIndex]
    return result
  }

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber
  }

  private static func isPathCharacter(_ character: Character) -> Bool {
    isWordCharacter(character) || character == "/"
  }

  private static func doctorValue(_ text: String, budget: Int) -> String {
    let full = percentEncode(text)
    if full.count <= budget {
      return full
    }
    var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    while !lines.isEmpty {
      lines.removeLast()
      let candidate = percentEncode((lines + [cutMarker]).joined(separator: "\n"))
      if candidate.count <= budget {
        return candidate
      }
    }
    let marker = percentEncode(cutMarker)
    return marker.count <= budget ? marker : ""
  }

  private static func percentEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
  }
}
