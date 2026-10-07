public enum CommandHelp {
  public static func isRequest(_ arguments: [String]) -> Bool {
    arguments.contains("--help") || arguments.contains("-h")
  }
}
