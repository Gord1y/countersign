import Foundation

struct ReleaseIndexError: Error, Equatable {
  let reason: String
}

enum ReleaseIndex {
  static func latestVersion(from data: Data) -> Result<String?, ReleaseIndexError> {
    let decoded: JSONValue
    do {
      decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      return .failure(ReleaseIndexError(reason: "index.json is not valid JSON"))
    }
    guard case .object(let root) = decoded else {
      return .failure(ReleaseIndexError(reason: "index.json does not contain a JSON object"))
    }
    guard let schemaVersion = root["schemaVersion"] else {
      return .failure(ReleaseIndexError(reason: "index.json is missing schemaVersion"))
    }
    guard case .int(1) = schemaVersion else {
      return .failure(ReleaseIndexError(reason: "index.json has an unknown schemaVersion"))
    }
    guard let releasesValue = root["releases"] else {
      return .failure(ReleaseIndexError(reason: "index.json is missing releases"))
    }
    guard case .array(let releases) = releasesValue else {
      return .failure(ReleaseIndexError(reason: "index.json releases is not an array"))
    }
    guard let first = releases.first else {
      return .success(nil)
    }
    guard case .object(let entry) = first else {
      return .failure(ReleaseIndexError(reason: "index.json releases[0] is not an object"))
    }
    guard case .string(let version)? = entry["version"] else {
      return .failure(ReleaseIndexError(reason: "index.json releases[0] is missing version"))
    }
    return .success(version)
  }
}
