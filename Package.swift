// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lights",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Lights",
            path: "Sources/Lights"
        )
    ]
)
