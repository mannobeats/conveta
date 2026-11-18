// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ConvetaKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ConvetaKit", targets: ["ConvetaKit"]),
    ],
    targets: [
        // Formats, probing, conversion engines and output planning. No UI, so it is testable alone.
        .target(name: "ConvetaKit"),
        .testTarget(name: "ConvetaKitTests", dependencies: ["ConvetaKit"]),
    ]
)
