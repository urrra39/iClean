// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iClean",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ICCore"),
        .executableTarget(name: "ic-hog"),
        .testTarget(name: "ICCoreTests", dependencies: ["ICCore"], exclude: ["Fixtures"]),
    ]
)
