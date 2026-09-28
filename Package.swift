// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StickyTop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "StickyTop", targets: ["StickyTop"]),
    ],
    targets: [
        // Pure model + persistence + geometry. No AppKit, fully unit-tested.
        .target(name: "StickyCore"),
        // The menu-bar app: floating note panels, status menu, hotkeys.
        .executableTarget(name: "StickyTop", dependencies: ["StickyCore"]),
        .testTarget(name: "StickyCoreTests", dependencies: ["StickyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
