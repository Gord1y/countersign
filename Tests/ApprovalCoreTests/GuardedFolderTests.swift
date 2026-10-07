import Foundation
import Testing

@testable import ApprovalCore

@Suite struct GuardedFolderTests {
  private let home = URL(fileURLWithPath: "/Users/qa-someone")

  @Test func foldersInPlacesMacOSGuardsAreNamedByPlace() {
    let cases: [(path: String, place: String)] = [
      ("/Users/qa-someone/Documents/a", "Documents"),
      ("/Users/qa-someone/Desktop/a", "Desktop"),
      ("/Users/qa-someone/Downloads/a", "Downloads"),
      ("/Users/qa-someone/Library/Mobile Documents/a", "iCloud Drive"),
      ("/Volumes/Drive/a", "an external drive"),
    ]
    for entry in cases {
      let folder = URL(fileURLWithPath: entry.path)
      #expect(GuardedFolder.isGuarded(folder, home: home))
      #expect(GuardedFolder.placeName(of: folder, home: home) == entry.place)
    }
  }

  @Test func theGuardedPlaceItselfIsGuarded() {
    #expect(GuardedFolder.isGuarded(home.appendingPathComponent("Documents"), home: home))
  }

  @Test func otherFoldersAreNotGuarded() {
    for path in [
      "/Users/qa-someone/countersign-skills", "/Users/qa-someone/Documentsx/a", "/opt/a",
    ] {
      let folder = URL(fileURLWithPath: path)
      #expect(!GuardedFolder.isGuarded(folder, home: home))
      #expect(GuardedFolder.placeName(of: folder, home: home) == nil)
    }
  }
}

@Suite struct SkillFolderApprovalsTests {
  @Test func addingTheSameFolderTwiceKeepsItOnce() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("qa-skill-folder-approvals-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("skill-folders-shown")
    let folder = URL(fileURLWithPath: "/Users/qa-someone/Documents/profile")

    try SkillFolderApprovals.add(folder, to: file)
    try SkillFolderApprovals.add(folder, to: file)

    #expect(SkillFolderApprovals.read(file) == [folder.path])
    #expect(
      try String(contentsOf: file, encoding: .utf8) == "/Users/qa-someone/Documents/profile\n")
  }

  @Test func aMissingFileReadsAsEmpty() {
    let file = FileManager.default.temporaryDirectory
      .appendingPathComponent("qa-missing-\(UUID().uuidString)")
    #expect(SkillFolderApprovals.read(file).isEmpty)
  }
}
