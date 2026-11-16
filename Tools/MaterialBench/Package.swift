// swift-tools-version: 6.0

// Herramienta de medida: reproduce un PGN con fischer-core y mide ChessMaterial.
// Paquete aparte para que la librería ChessMaterial no tenga dependencias.

import PackageDescription

let package = Package(
    name: "MaterialBench",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/NSStudent/fischer-core.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "material-bench",
            dependencies: [
                .product(name: "ChessMaterial", package: "ChessMaterial"),
                .product(name: "FischerCore", package: "fischer-core"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
