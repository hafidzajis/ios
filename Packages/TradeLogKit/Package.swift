// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TradeLogKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TradeLogCore", targets: ["TradeLogCore"]),
        .library(name: "TradeLogIntegrations", targets: ["TradeLogIntegrations"]),
    ],
    dependencies: [
        // CryptoKit is Apple-only; swift-crypto provides the same API on Linux (CI / tests).
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "TradeLogCore"),
        .target(
            name: "TradeLogIntegrations",
            dependencies: [
                "TradeLogCore",
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ]
        ),
        .testTarget(name: "TradeLogCoreTests", dependencies: ["TradeLogCore"]),
        .testTarget(
            name: "TradeLogIntegrationsTests",
            dependencies: ["TradeLogIntegrations"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
