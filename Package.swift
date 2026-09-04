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
    dependencies: [
        .package(url: "https://github.com/openid/AppAuth-iOS.git", exact: "3.0.0"),
    ],
    targets: [
        .target(name: "PinbookCore", dependencies: [.product(name: "AppAuthCore", package: "AppAuth-iOS")]),
        .testTarget(name: "PinbookCoreTests", dependencies: ["PinbookCore"], resources: [.copy("Fixtures")]),
    ]
)
