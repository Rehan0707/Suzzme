// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SuzzmeSpeechKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SuzzmeSpeechKit", targets: ["SuzzmeSpeechKit"])],
    targets: [.target(name: "SuzzmeSpeechKit")]
)
