import Foundation

struct DiscountCode: Hashable, Sendable {
  let code: String
  let rate: Decimal
  let expiresAt: Date?
}

let maximumDiscountRate: Decimal = 0.5

func applyDiscount(to total: Decimal, code: String?) -> Decimal {
  guard let code, !code.isEmpty else {
    return total
  }
  let rate = discountRate(for: code)
  return total * (1 - rate)
}

func discountRate(for code: String, now: Date = Date()) -> Decimal {
  guard let discount = DiscountCatalog.shared.discount(named: code) else {
    return 0
  }
  if let expiresAt = discount.expiresAt, expiresAt < now {
    return 0
  }
  return discount.rate
}

final class DiscountCatalog: Sendable {
  static let shared = DiscountCatalog(codes: [])

  private let codes: [String: DiscountCode]

  init(codes: [DiscountCode]) {
    self.codes = Dictionary(uniqueKeysWithValues: codes.map { ($0.code.uppercased(), $0) })
  }

  func discount(named name: String) -> DiscountCode? {
    codes[name.uppercased()]
  }
}
