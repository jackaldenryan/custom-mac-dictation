// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CustomMacDictation",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "CustomDictation", targets: ["CustomDictation"]),
        .library(name: "CustomDictationKit", targets: ["CustomDictationKit"])
    ],
    targets: [
        .target(
            name: "CustomDictationKit",
            path: "Sources/CustomDictationKit",
            resources: [.copy("Defaults")]
        ),
        .executableTarget(
            name: "CustomDictation",
            dependencies: ["CustomDictationKit"],
            path: "Sources/CustomDictation"
        ),
        .executableTarget(
            name: "CheckLogic",
            dependencies: ["CustomDictationKit"],
            path: "Sources/CheckLogic"
        )
    ]
)
