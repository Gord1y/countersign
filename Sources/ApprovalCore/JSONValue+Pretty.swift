import Foundation

extension JSONValue {
  public var prettyPrinted: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8)
    else {
      return "null"
    }
    return string
  }
}
