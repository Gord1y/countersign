import Foundation

struct LineItem: Hashable, Sendable {
  let sku: String
  let price: Decimal
  let quantity: Int
}

struct Order: Sendable {
  let id: UUID
  let lineItems: [LineItem]
  let discountCode: String?
}

struct CheckoutService: Sendable {
  let taxCalculator: TaxCalculator

  func subtotal(for order: Order) -> Decimal {
    order.lineItems.reduce(0) { $0 + $1.price * Decimal($1.quantity) }
  }

  func total(for order: Order) -> Decimal {
    let subtotal = subtotal(for: order)
    let tax = taxCalculator.tax(on: subtotal)
    return subtotal + tax
  }
}
