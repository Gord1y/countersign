import Foundation

public struct SkillCatalogError: Error, Equatable, Sendable {
  public let reason: String

  public init(reason: String) {
    self.reason = reason
  }
}

public struct SkillCatalog: Equatable, Sendable {
  public enum Invocation: String, Equatable, Sendable {
    case model
    case manual
  }

  public struct Skill: Equatable, Sendable {
    public let name: String
    public let version: String
    public let agents: [String]
    public let description: String
    public let whenToUse: String?
    public let invocation: Invocation
    public let path: String

    public init(
      name: String,
      version: String,
      agents: [String],
      description: String,
      whenToUse: String?,
      invocation: Invocation,
      path: String
    ) {
      self.name = name
      self.version = version
      self.agents = agents
      self.description = description
      self.whenToUse = whenToUse
      self.invocation = invocation
      self.path = path
    }
  }

  public struct Rule: Equatable, Sendable {
    public let name: String
    public let title: String
    public let agents: [String]
    public let path: String

    public init(name: String, title: String, agents: [String], path: String) {
      self.name = name
      self.title = title
      self.agents = agents
      self.path = path
    }
  }

  public struct Agent: Equatable, Sendable {
    public let name: String
    public let description: String
    public let model: String?
    public let path: String

    public init(name: String, description: String, model: String?, path: String) {
      self.name = name
      self.description = description
      self.model = model
      self.path = path
    }
  }

  public static let fileName = "catalog.json"

  public let skills: [Skill]
  public let rules: [Rule]
  public let agents: [Agent]

  public init(skills: [Skill], rules: [Rule], agents: [Agent]) {
    self.skills = skills
    self.rules = rules
    self.agents = agents
  }

  public static func parse(_ data: Data) -> Result<SkillCatalog, SkillCatalogError> {
    do {
      return .success(try decode(data))
    } catch let error as SkillCatalogError {
      return .failure(error)
    } catch {
      return .failure(SkillCatalogError(reason: "\(fileName) is not valid JSON"))
    }
  }

  public static func read(folder: URL) -> Result<SkillCatalog, SkillCatalogError> {
    let file = folder.appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: file) else {
      return .failure(SkillCatalogError(reason: "\(fileName) is missing in \(folder.path)"))
    }
    return parse(data)
  }

  private static func decode(_ data: Data) throws -> SkillCatalog {
    let decoded: JSONValue
    do {
      decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      throw SkillCatalogError(reason: "\(fileName) is not valid JSON")
    }
    guard case .object(let root) = decoded else {
      throw SkillCatalogError(reason: "\(fileName) does not contain a JSON object")
    }
    guard let schemaVersion = root["schemaVersion"] else {
      throw SkillCatalogError(reason: "\(fileName) is missing schemaVersion")
    }
    guard case .int(1) = schemaVersion else {
      throw SkillCatalogError(reason: "\(fileName) has an unknown schemaVersion")
    }
    return SkillCatalog(
      skills: try entries(root, list: "skills", parse: skill),
      rules: try entries(root, list: "rules", parse: rule),
      agents: try entries(root, list: "agents", parse: agent)
    )
  }

  private static func entries<Entry>(
    _ root: [String: JSONValue],
    list: String,
    parse: (_ entry: [String: JSONValue], _ location: String) throws -> Entry
  ) throws -> [Entry] {
    guard let value = root[list] else { return [] }
    guard case .array(let items) = value else {
      throw SkillCatalogError(reason: "\(fileName) \(list) is not an array")
    }
    var parsed: [Entry] = []
    for (index, item) in items.enumerated() {
      let location = "\(list)[\(index)]"
      guard case .object(let entry) = item else {
        throw SkillCatalogError(reason: "\(fileName) \(location) is not an object")
      }
      parsed.append(try parse(entry, location))
    }
    return parsed
  }

  private static func skill(_ entry: [String: JSONValue], _ location: String) throws -> Skill {
    let name = try requiredString(entry, "name", location)
    let version = try requiredString(entry, "version", location)
    let agents = try requiredStrings(entry, "agents", location)
    let description = try requiredString(entry, "description", location)
    let whenToUse = try optionalString(entry, "whenToUse", location)
    let invocationName = try requiredString(entry, "invocation", location)
    guard let invocation = Invocation(rawValue: invocationName) else {
      throw SkillCatalogError(reason: "\(fileName) \(location) has an unknown invocation")
    }
    let path = try requiredPath(entry, location)
    return Skill(
      name: name, version: version, agents: agents, description: description,
      whenToUse: whenToUse, invocation: invocation, path: path)
  }

  private static func rule(_ entry: [String: JSONValue], _ location: String) throws -> Rule {
    Rule(
      name: try requiredString(entry, "name", location),
      title: try requiredString(entry, "title", location),
      agents: try requiredStrings(entry, "agents", location),
      path: try requiredPath(entry, location))
  }

  private static func agent(_ entry: [String: JSONValue], _ location: String) throws -> Agent {
    Agent(
      name: try requiredString(entry, "name", location),
      description: try requiredString(entry, "description", location),
      model: try optionalString(entry, "model", location),
      path: try requiredPath(entry, location))
  }

  private static func missing(_ field: String, _ location: String) -> SkillCatalogError {
    SkillCatalogError(reason: "\(fileName) \(location) is missing \(field)")
  }

  private static func requiredString(
    _ entry: [String: JSONValue], _ field: String, _ location: String
  ) throws -> String {
    guard let value = entry[field]?.stringValue else { throw missing(field, location) }
    return value
  }

  private static func optionalString(
    _ entry: [String: JSONValue], _ field: String, _ location: String
  ) throws -> String? {
    switch entry[field] {
    case nil, .null?:
      return nil
    case .string(let value)?:
      return value
    default:
      throw missing(field, location)
    }
  }

  private static func requiredStrings(
    _ entry: [String: JSONValue], _ field: String, _ location: String
  ) throws -> [String] {
    guard let items = entry[field]?.arrayValue else { throw missing(field, location) }
    return try items.map { item in
      guard let value = item.stringValue else { throw missing(field, location) }
      return value
    }
  }

  private static func requiredPath(_ entry: [String: JSONValue], _ location: String) throws
    -> String
  {
    let path = try requiredString(entry, "path", location)
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    if path.isEmpty || path.hasPrefix("/") || components.contains("..") {
      throw SkillCatalogError(reason: "\(fileName) \(location) has a path outside its folder")
    }
    return path
  }
}
