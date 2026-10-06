public enum CommandHelp {
  public static func isRequest(_ arguments: [String]) -> Bool {
    arguments == ["--help"] || arguments == ["-h"]
  }
}
