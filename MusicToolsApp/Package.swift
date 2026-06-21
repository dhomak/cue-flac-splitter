// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MusicTools",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "MusicTools",
            path: "Sources/MusicTools"
        )
    ]
)
