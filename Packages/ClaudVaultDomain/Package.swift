// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudVaultDomain",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "ClaudVaultDomain",
            targets: ["ClaudVaultDomain"]
        )
    ],
    targets: [
        .target(
            name: "ClaudVaultDomain",
            path: "Sources/ClaudVaultDomain"
        )
    ],
    // Swift 5 language mode — код домена писался под Swift 5
    // (app-таргет SWIFT_VERSION = 5.0); strict concurrency Swift 6
    // даст сотни ошибок Sendable/region isolation.
    swiftLanguageModes: [.v5]
)
