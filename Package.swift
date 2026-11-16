// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChessMaterial",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ChessMaterial", targets: ["ChessMaterial"]),
    ],
    targets: [
        .target(
            name: "ChessMaterial",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ChessMaterialTests",
            dependencies: ["ChessMaterial"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
