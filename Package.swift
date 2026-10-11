// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesktopRugCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "DesktopRugCore", targets: ["DesktopRugCore"])],
    targets: [
        .target(name: "DesktopRugCore", path: "DesktopRug/Core"),
        .testTarget(name: "DesktopRugCoreTests", dependencies: ["DesktopRugCore"], path: "DesktopRugTests")
    ]
)
