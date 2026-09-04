// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinbookCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PinbookCore", targets: ["PinbookCore"]),
    ],
    targets: [
        .target(name: "PinbookCore"),
        .testTarget(name: "PinbookCoreTests", dependencies: ["PinbookCore"], resources: [.copy("Fixtures")]),
    ]
)
