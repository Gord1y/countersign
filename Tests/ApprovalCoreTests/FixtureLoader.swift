import Foundation

enum FixtureLoader {
  enum LoaderError: Error {
    case missing(String)
  }

  static func data(_ name: String, withExtension fileExtension: String = "json") throws -> Data {
    guard
      let url = Bundle.module.url(
        forResource: name, withExtension: fileExtension, subdirectory: "Fixtures")
    else {
      throw LoaderError.missing(name)
    }
    return try Data(contentsOf: url)
  }
}
