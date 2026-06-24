// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SimpleMounter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SimpleMounter",
            path: "Sources/SimpleMounter"
        )
    ]
)
