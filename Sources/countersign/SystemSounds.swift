import AppKit
import ApprovalCore

enum SystemSounds {
  private static let folder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

  static var installedNames: [String] {
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    let names = files.filter { $0.pathExtension == "aiff" }
      .map { $0.deletingPathExtension().lastPathComponent }
      .sorted()
    return names.isEmpty ? PanelSound.systemNames : names
  }

  @MainActor
  static func play(_ name: String) {
    guard !PanelSound.isSilent(name) else { return }
    NSSound(named: NSSound.Name(name))?.play()
  }
}
