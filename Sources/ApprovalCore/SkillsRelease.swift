import CryptoKit
import Foundation

public struct SkillsReleaseError: Error, Equatable, Sendable {
  public let reason: String

  public init(reason: String) {
    self.reason = reason
  }
}

public struct SkillsRelease: Equatable, Sendable {
  public static let repository = "Gord1y/countersign-skills"

  private static let digestLength = 64
  private static let separator = "  "
  private static let assetNameCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
  private static let lowercaseHexCharacters = CharacterSet(charactersIn: "0123456789abcdef")

  public let version: String

  public init?(version: String) {
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    for part in parts {
      guard !part.isEmpty, part.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }) else {
        return nil
      }
    }
    self.version = version
  }

  public var tag: String {
    "v\(version)"
  }

  public var archiveName: String {
    "countersign-skills-\(version).tar.gz"
  }

  public var checksumName: String {
    archiveName + ".sha256"
  }

  public func assetURL(named name: String) -> URL? {
    guard
      !name.isEmpty,
      name != ".",
      name != "..",
      name.unicodeScalars.allSatisfy({ Self.assetNameCharacters.contains($0) })
    else { return nil }
    return URL(
      string:
        "https://github.com/\(Self.repository)/releases/download/\(tag)/\(name)")
  }

  public func expectedDigest(fromChecksumFile data: Data) -> Result<String, SkillsReleaseError> {
    let shapeError = SkillsReleaseError(
      reason: "the checksum file is not one line of a SHA-256 and a file name")
    guard var text = String(data: data, encoding: .utf8) else { return .failure(shapeError) }
    if text.hasSuffix("\n") {
      text.removeLast()
    }
    guard !text.contains("\n"), !text.contains("\r") else { return .failure(shapeError) }
    let digest = String(text.prefix(Self.digestLength))
    let rest = text.dropFirst(Self.digestLength)
    guard
      digest.count == Self.digestLength,
      digest.unicodeScalars.allSatisfy({ Self.lowercaseHexCharacters.contains($0) }),
      rest.hasPrefix(Self.separator)
    else { return .failure(shapeError) }
    let name = String(rest.dropFirst(Self.separator.count))
    guard
      !name.isEmpty,
      name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    else { return .failure(shapeError) }
    guard name == archiveName else {
      return .failure(
        SkillsReleaseError(reason: "the checksum is for \(name), not \(archiveName)"))
    }
    return .success(digest)
  }

  public func verify(archive: Data, checksumFile: Data) -> Result<Void, SkillsReleaseError> {
    switch expectedDigest(fromChecksumFile: checksumFile) {
    case .failure(let error):
      return .failure(error)
    case .success(let digest):
      guard Self.sha256Hex(of: archive) == digest else {
        return .failure(
          SkillsReleaseError(
            reason: "the archive's SHA-256 does not match its checksum file"))
      }
      return .success(())
    }
  }

  public static func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
