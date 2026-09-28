import Foundation

public enum SessionRegistry {
  public struct Entry: Sendable, Equatable {
    public let url: URL
    public let fields: [String: JSONValue]

    public init(url: URL, fields: [String: JSONValue]) {
      self.url = url
      self.fields = fields
    }
  }

  public static func findEntry(sessionID: String, in directory: URL) -> Entry? {
    guard
      let contents = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return nil
    }
    var best: Entry?
    var bestDate = Date.distantPast
    for fileURL in contents where fileURL.pathExtension == "json" {
      guard let fields = readFields(at: fileURL), fields["sessionId"]?.stringValue == sessionID
      else {
        continue
      }
      let modificationDate =
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? Date.distantPast
      if best == nil || modificationDate > bestDate {
        best = Entry(url: fileURL, fields: fields)
        bestDate = modificationDate
      }
    }
    return best
  }

  private static func readFields(at url: URL) -> [String: JSONValue]? {
    guard let data = try? Data(contentsOf: url),
      let value = try? JSONDecoder().decode(JSONValue.self, from: data),
      case .object(let fields) = value
    else {
      return nil
    }
    return fields
  }
}
