// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "AAXConnectSwift",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "AAXConnectSwift",
            targets: ["AAXConnectSwift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "AAXConnectSwift",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "AAXConnectSwiftTests",
            dependencies: ["AAXConnectSwift"]
        ),
    ]
)