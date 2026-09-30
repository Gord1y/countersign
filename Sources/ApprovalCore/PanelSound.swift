public enum PanelSound {
  public static let none = "none"

  public static let systemNames: [String] = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
    "Sosumi", "Submarine", "Tink",
  ]

  public static func choices(installed: [String]) -> [String] {
    [none] + installed
  }

  public static func isSilent(_ name: String) -> Bool {
    name == none
  }

  public static func title(_ name: String) -> String {
    isSilent(name) ? "None" : name
  }
}
