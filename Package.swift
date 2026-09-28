// swift-tools-version:6.0
import PackageDescription

let package = Package(
  name: "countersign",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "countersign", targets: ["countersign"])
  ],
  targets: [
    .target(name: "ApprovalCore"),
    .executableTarget(name: "countersign", dependencies: ["ApprovalCore"]),
    .executableTarget(name: "ticket-probe", dependencies: ["ApprovalCore"]),
    .testTarget(
      name: "ApprovalCoreTests",
      dependencies: ["ApprovalCore", "ticket-probe"],
      resources: [.copy("Fixtures")]
    ),
  ]
)
