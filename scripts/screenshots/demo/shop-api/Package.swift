// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "shop-api",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "Checkout")
  ]
)
