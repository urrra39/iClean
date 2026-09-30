// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iClean",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ICCore"),
        .target(name: "ICSystem", dependencies: ["ICCore"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreAudio"),
                                 .linkedFramework("CoreMediaIO"), .linkedFramework("AppKit")]),
        .executableTarget(name: "icleand", dependencies: ["ICSystem"]),
        .executableTarget(name: "iclean", dependencies: ["ICCore", "ICSystem"]),
        .executableTarget(name: "iCleanMenu", dependencies: ["ICCore", "ICSystem"], resources: [.process("Resources")]),
        .executableTarget(name: "ic-hog"),
        .testTarget(name: "ICCoreTests", dependencies: ["ICCore"], exclude: ["Fixtures"]),
        .testTarget(name: "ICSystemTests", dependencies: ["ICCore", "ICSystem", "ic-hog", "icleand", "iclean"]),
    ]
)
