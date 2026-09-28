import Foundation

public struct AppBundleLinkOffer: Sendable, Equatable {
  public let target: String
  public let link: URL

  public init(target: String, link: URL) {
    self.target = target
    self.link = link
  }
}

public enum AppBundleLink {
  public static let bundleName = "Countersign.app"
  static let cellarMarker = "/Cellar/countersign/"
  static let optDirectory = "/opt/countersign/"

  public static func candidate(forResolvedExecutable path: String) -> String {
    URL(fileURLWithPath: path)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(bundleName)
      .standardizedFileURL.path
  }

  public static func stableTarget(for candidate: String) -> String {
    guard let marker = candidate.range(of: cellarMarker) else { return candidate }
    let prefix = candidate[..<marker.lowerBound]
    let inKeg = candidate[marker.upperBound...].drop { $0 != "/" }.dropFirst()
    guard !inKeg.isEmpty else { return candidate }
    return String(prefix) + optDirectory + String(inKeg)
  }

  public static func link(home: URL) -> URL {
    home.appendingPathComponent("Applications").appendingPathComponent(bundleName)
  }

  public static func offer(resolvedExecutable: String, home: URL, exists: (String) -> Bool)
    -> AppBundleLinkOffer?
  {
    let candidate = candidate(forResolvedExecutable: resolvedExecutable)
    let link = link(home: home)
    guard exists(candidate), !exists(link.path) else { return nil }
    return AppBundleLinkOffer(target: stableTarget(for: candidate), link: link)
  }
}
