// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Titiz",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TitizCore",
            targets: ["TitizCore"]
        ),
        .executable(
            name: "TitizEval",
            targets: ["TitizEval"]
        ),
        .executable(
            name: "TitizApp",
            targets: ["TitizApp"]
        )
    ],
    targets: [
        .target(
            name: "CHunspell",
            path: "Sources/CHunspell",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("hunspell"),
                .define("HUNSPELL_STATIC"),
                .define("BUILDING_LIBHUNSPELL")
            ]
        ),
        .target(
            name: "TitizCore",
            dependencies: ["CHunspell"],
            path: "Sources/TitizCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TitizEval",
            dependencies: ["TitizCore"],
            path: "Sources/TitizEval"
        ),
        .executableTarget(
            name: "TitizApp",
            dependencies: ["TitizCore"],
            path: "Sources/TitizApp"
        ),
        .testTarget(
            name: "TitizCoreTests",
            dependencies: ["TitizCore"],
            path: "Tests/TitizCoreTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
