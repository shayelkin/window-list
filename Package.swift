// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let propertyBased: Target.Dependency = .product(name: "PropertyBased", package: "swift-property-based")

let package = Package(
    name: "WindowList",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "WindowListCore", targets: ["WindowListCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based", exact: "2.0.1")
    ],
    targets: [
        .target(
            name: "WindowListCore",
            swiftSettings: swiftSettings,
            linkerSettings: [
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks"]),
                .linkedFramework("SkyLight"),
            ]
        ),
        .executableTarget(name: "AXFixture", dependencies: ["WindowListCore"], swiftSettings: swiftSettings),
        .target(name: "AXTestSupport", dependencies: ["WindowListCore"], swiftSettings: swiftSettings),
        .testTarget(
            name: "WindowListCoreTests",
            dependencies: ["WindowListCore", propertyBased],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AXTestSupportTests",
            dependencies: ["AXTestSupport", propertyBased],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "WindowListAXTests",
            dependencies: ["WindowListCore", "AXTestSupport", "AXFixture", propertyBased],
            swiftSettings: swiftSettings
        ),
    ]
)
