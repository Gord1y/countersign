import Foundation

struct TaxCalculator: Sendable {
  let rate: Decimal

  func tax(on amount: Decimal) -> Decimal {
    amount * rate
  }
}
