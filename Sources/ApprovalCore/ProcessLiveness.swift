import Darwin

enum ProcessLiveness {
  struct Snapshot {
    let startTime: UInt64
    let isZombie: Bool
    let parentPID: Int32
  }

  static func startTime(of pid: Int32) -> UInt64? {
    snapshot(of: pid)?.startTime
  }

  static func isAlive(pid: Int32, processStart: UInt64?) -> Bool {
    guard pid > 0 else { return false }
    guard kill(pid, 0) == 0 || errno == EPERM else { return false }
    guard let snapshot = snapshot(of: pid) else { return true }
    guard !snapshot.isZombie else { return false }
    guard let processStart else { return true }
    return snapshot.startTime == processStart
  }

  static func parentPID(of pid: Int32) -> Int32? {
    guard let snapshot = snapshot(of: pid), snapshot.parentPID > 0 else { return nil }
    return snapshot.parentPID
  }

  private static func snapshot(of pid: Int32) -> Snapshot? {
    guard pid > 0 else { return nil }
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    let result = mib.withUnsafeMutableBufferPointer { mibPointer in
      sysctl(mibPointer.baseAddress, u_int(mibPointer.count), &info, &size, nil, 0)
    }
    guard result == 0, size == MemoryLayout<kinfo_proc>.stride, info.kp_proc.p_pid == pid else {
      return nil
    }
    let startTime = info.kp_proc.p_un.__p_starttime
    guard startTime.tv_sec >= 0, startTime.tv_usec >= 0 else { return nil }
    let start = UInt64(startTime.tv_sec) * 1_000_000 + UInt64(startTime.tv_usec)
    return Snapshot(
      startTime: start, isZombie: info.kp_proc.p_stat == SZOMB, parentPID: info.kp_eproc.e_ppid)
  }
}
