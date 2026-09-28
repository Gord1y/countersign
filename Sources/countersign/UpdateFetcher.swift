import ApprovalCore
import Foundation

enum UpdateFetcher {
  static let indexURL = URL(
    string: "https://raw.githubusercontent.com/Gord1y/countersign/main/releases/index.json")

  static func fetch(currentVersion: String) async -> UpdateCheckOutcome {
    guard let indexURL else { return .unknown(reason: "invalid index URL") }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    let session = URLSession(configuration: configuration)
    var request = URLRequest(url: indexURL)
    request.httpMethod = "GET"
    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return .unknown(reason: "no HTTP response")
      }
      guard httpResponse.statusCode == 200 else {
        return .unknown(reason: "HTTP \(httpResponse.statusCode)")
      }
      return UpdateCheck.evaluate(indexData: data, currentVersion: currentVersion)
    } catch {
      return .unknown(reason: "network error: \(error.localizedDescription)")
    }
  }
}
