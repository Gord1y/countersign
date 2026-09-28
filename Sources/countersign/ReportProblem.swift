import ApprovalCore
import Foundation

enum ReportProblem {
  static func url() -> URL? {
    let doctorText = Doctor.report(DoctorCommand.gatherInput()).map(\.text).joined(
      separator: "\n")
    return BugReportURL.build(
      macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      countersignVersion: CountersignVersion.current, doctorText: doctorText,
      homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
  }
}
