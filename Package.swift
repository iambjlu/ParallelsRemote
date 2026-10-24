// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ParallelsRemote",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ParallelsRemote",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
