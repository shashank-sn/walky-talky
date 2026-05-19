// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WalkyTalky",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WalkyTalky", targets: ["WalkyTalky"])
    ],
    targets: [
        .executableTarget(
            name: "WalkyTalky",
            path: "Sources/WalkyTalky",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
