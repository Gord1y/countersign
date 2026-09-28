import Foundation

enum LegacyDiscount {
  static func percentOff(_ total: Decimal, percent: Int) -> Decimal {
    total - total * Decimal(percent) / 100
  }
}
