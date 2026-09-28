public enum ProcessAncestry {
  public static let defaultMaxSteps = 64

  public static func chain(
    from pid: Int32,
    maxSteps: Int = ProcessAncestry.defaultMaxSteps,
    parentOf: ((Int32) -> Int32?)? = nil
  ) -> [Int32] {
    let parentOf = parentOf ?? ProcessLiveness.parentPID(of:)
    var result: [Int32] = []
    var visited: Set<Int32> = []
    var current: Int32? = pid
    while let value = current, value > 0, !visited.contains(value), result.count < maxSteps {
      result.append(value)
      visited.insert(value)
      if value == 1 {
        break
      }
      current = parentOf(value)
    }
    return result
  }
}
