// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iClear",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ICCore"),
        .target(
            name: "ICSystem", dependencies: ["ICCore"],
            linkerSettings: [
                .linkedFramework("IOKit"), .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMediaIO"), .linkedFramework("AppKit"),
            ]),
        .executableTarget(name: "icleard", dependencies: ["ICSystem"]),
        .executableTarget(name: "iclear", dependencies: ["ICCore", "ICSystem"]),
        .executableTarget(name: "iClearMenu", dependencies: ["ICCore", "ICSystem"], resources: [.process("Resources")]),
        .executableTarget(name: "ic-hog"),
        .testTarget(name: "ICCoreTests", dependencies: ["ICCore"], exclude: ["Fixtures"]),
        .testTarget(name: "ICSystemTests", dependencies: ["ICCore", "ICSystem", "ic-hog", "icleard", "iclear"]),
    ]
)
