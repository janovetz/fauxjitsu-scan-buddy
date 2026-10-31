// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScanButton",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScanButton", targets: ["ScanButton"]),
        .executable(name: "scan-check", targets: ["scan-check"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSane",
            pkgConfig: "sane-backends",
            providers: [.brew(["sane-backends"])]
        ),
        .target(name: "ScanKit", dependencies: ["CSane"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "ScanButton", dependencies: ["ScanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "scan-check", dependencies: ["ScanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ScanKitTests", dependencies: ["ScanKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
