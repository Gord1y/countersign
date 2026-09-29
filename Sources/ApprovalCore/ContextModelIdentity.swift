import Foundation

public struct ContextModelIdentity: Codable, Sendable, Equatable {
  public var modelID: String?
  public var scannedThrough: UInt64

  public init(modelID: String?, scannedThrough: UInt64) {
    self.modelID = modelID
    self.scannedThrough = scannedThrough
  }
}
