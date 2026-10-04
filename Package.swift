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
            resources: [.copy("Defaults")],
            linkerSettings: [
                .linkedFramework("InputMethodKit"),
                .linkedFramework("Carbon")
            ]
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
        ),
        .executableTarget(
            name: "CheckPhraseRules",
            dependencies: ["CustomDictationKit"],
            path: "Sources/CheckPhraseRules"
        ),
        .executableTarget(
            name: "CheckFieldScenarios",
            dependencies: ["CustomDictationKit"],
            path: "Sources/CheckFieldScenarios"
        ),
        .executableTarget(
            name: "CheckConfigMatrix",
            dependencies: ["CustomDictationKit"],
            path: "Sources/CheckConfigMatrix"
        ),
        .executableTarget(
            name: "ProbeSpeech",
            dependencies: ["CustomDictationKit"],
            path: "Sources/ProbeSpeech"
        )
    ]
)
