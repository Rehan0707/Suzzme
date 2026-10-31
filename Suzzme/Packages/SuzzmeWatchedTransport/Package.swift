// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SuzzmeWatchedTransport",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SuzzmeWatchedTransport", targets: ["SuzzmeWatchedTransport"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.5"),
    ],
    targets: [
        .target(name: "SuzzmeWatchedTransport", dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            .product(name: "NIOHTTP1", package: "swift-nio"),
            .product(name: "NIOTLS", package: "swift-nio"),
            .product(name: "NIOSSL", package: "swift-nio-ssl"),
        ]),
        .testTarget(name: "SuzzmeWatchedTransportTests", dependencies: ["SuzzmeWatchedTransport"],
                    path: "Tests/SuzzmeWatchedTransportTests"),
    ],
    swiftLanguageModes: [.v6]
)
